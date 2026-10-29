import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LEAFLET from '@salesforce/resourceUrl/frotaLeaflet';
import FONTES from '@salesforce/resourceUrl/frotaFontes';
import getCarretas from '@salesforce/apex/FrotaMapaController.getCarretas';
import sincronizarAgora from '@salesforce/apex/FrotaMapaController.sincronizarAgora';

const INTERVALO_LEITURA_MS = 30000;
// Tempo para o job de sincronização terminar antes de reler as posições.
const ESPERA_APOS_SINCRONIZAR_MS = 8000;
const DURACAO_DESLIZE_MS = 1500;
const CENTRO_BRASIL = [-15.78, -47.93];
const ZOOM_UMA_CARRETA = 15;
const TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const TILE_ATRIBUICAO = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';

const STATUS = {
    EM_ROTA: { label: 'Em rota', classe: 'em-rota' },
    PARADA: { label: 'Parada', classe: 'parada' },
    SEM_SINAL: { label: 'Sem sinal', classe: 'sem-sinal' }
};

const FORMATO_PREVISAO = new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
});

function reduceErrors(error) {
    const erros = Array.isArray(error) ? error : [error];
    return erros
        .filter(Boolean)
        .map((e) => e.body?.message || e.message || String(e))
        .join(', ');
}

function tempoDesde(dataIso) {
    if (!dataIso) {
        return 'sem posição';
    }
    const minutos = Math.round((Date.now() - new Date(dataIso).getTime()) / 60000);
    if (minutos < 1) {
        return 'agora';
    }
    if (minutos < 60) {
        return `há ${minutos} min`;
    }
    const horas = Math.round(minutos / 60);
    return horas < 24 ? `há ${horas} h` : `há ${Math.round(horas / 24)} d`;
}

function movimentoReduzido() {
    return window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
}

export default class FrotaMapa extends NavigationMixin(LightningElement) {
    _recordId = null;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(valor) {
        this._recordId = valor || null;
    }

    carretas = [];
    erro;
    carregando = true;
    sincronizando = false;
    ultimaLeitura;
    selecionadaId;
    busca = '';
    statusAtivos = [];

    wiredCarretas;
    leafletCarregado = false;
    carregandoLeaflet = false;
    mapa;
    marcadores = new Map();
    jaCentralizou = false;
    intervaloLeitura;

    @wire(getCarretas, { recordId: '$_recordId' })
    receberCarretas(resultado) {
        this.wiredCarretas = resultado;
        if (resultado.data) {
            this.carretas = resultado.data.map((c) => ({ ...c }));
            this.erro = undefined;
            this.carregando = false;
            this.ultimaLeitura = new Date();
            if (!this.modoFrota && this.carretas.length) {
                this.selecionadaId = this.carretas[0].id;
            }
            this.desenharMarcadores();
        } else if (resultado.error) {
            this.erro = reduceErrors(resultado.error);
            this.carregando = false;
        }
    }

    connectedCallback() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.intervaloLeitura = setInterval(() => this.reler(), INTERVALO_LEITURA_MS);
    }

    disconnectedCallback() {
        clearInterval(this.intervaloLeitura);
        this.marcadores.forEach((item) => cancelAnimationFrame(item.animacao));
        if (this.mapa) {
            this.mapa.remove();
            this.mapa = undefined;
            this.marcadores.clear();
        }
    }

    renderedCallback() {
        if (this.leafletCarregado || this.carregandoLeaflet) {
            return;
        }
        this.carregandoLeaflet = true;
        Promise.all([
            loadScript(this, `${LEAFLET}/leaflet.js`),
            loadStyle(this, `${LEAFLET}/leaflet.css`),
            loadStyle(this, `${FONTES}/fontes.css`)
        ])
            .then(() => {
                this.leafletCarregado = true;
                this.iniciarMapa();
            })
            .catch((error) => {
                this.erro = 'O mapa não carregou: ' + reduceErrors(error);
            });
    }

    // ---------- Mapa ----------

    iniciarMapa() {
        const L = window.L;
        this.mapa = L.map(this.refs.mapa, { zoomControl: false }).setView(CENTRO_BRASIL, 4);
        L.control.zoom({ position: 'bottomright' }).addTo(this.mapa);
        L.tileLayer(TILE_URL, { maxZoom: 19, attribution: TILE_ATRIBUICAO }).addTo(this.mapa);
        if (this.modoFrota) {
            this.mapa.on('click', () => {
                this.selecionadaId = undefined;
                this.atualizarIcones();
            });
        }
        this.desenharMarcadores();
    }

    desenharMarcadores() {
        if (!this.mapa) {
            return;
        }
        const L = window.L;
        const visiveis = new Set(this.carretasFiltradasBase.map((c) => c.id));

        this.carretas.forEach((carreta) => {
            const destino = [carreta.latitude, carreta.longitude];
            const item = this.marcadores.get(carreta.id);
            if (!item) {
                const marcador = L.marker(destino, {
                    icon: this.criarIcone(carreta),
                    keyboard: false,
                    riseOnHover: true
                }).on('click', (evento) => {
                    L.DomEvent.stopPropagation(evento);
                    this.selecionar(carreta.id, false);
                });
                this.marcadores.set(carreta.id, { marcador, chaveIcone: this.chaveIcone(carreta) });
            } else {
                this.deslizar(item, destino);
            }
            this.alternarVisibilidade(this.marcadores.get(carreta.id).marcador, visiveis.has(carreta.id));
        });

        const atuais = new Set(this.carretas.map((c) => c.id));
        this.marcadores.forEach((item, id) => {
            if (!atuais.has(id)) {
                cancelAnimationFrame(item.animacao);
                item.marcador.remove();
                this.marcadores.delete(id);
            }
        });

        this.atualizarIcones();

        if (!this.jaCentralizou && this.carretas.length) {
            this.centralizar();
            this.jaCentralizou = true;
        }
    }

    alternarVisibilidade(marcador, visivel) {
        if (visivel && !this.mapa.hasLayer(marcador)) {
            marcador.addTo(this.mapa);
        } else if (!visivel && this.mapa.hasLayer(marcador)) {
            marcador.remove();
        }
    }

    // A carreta desliza até a nova posição em vez de pular: é o momento em que a frota "anda" na tela.
    deslizar(item, destino) {
        const L = window.L;
        const origem = item.marcador.getLatLng();
        const alvo = L.latLng(destino);
        if (origem.equals(alvo)) {
            return;
        }
        cancelAnimationFrame(item.animacao);
        if (movimentoReduzido() || !this.mapa.hasLayer(item.marcador)) {
            item.marcador.setLatLng(alvo);
            return;
        }
        const inicio = performance.now();
        const passo = (agora) => {
            const t = Math.min((agora - inicio) / DURACAO_DESLIZE_MS, 1);
            const suave = 1 - Math.pow(1 - t, 3);
            item.marcador.setLatLng([
                origem.lat + (alvo.lat - origem.lat) * suave,
                origem.lng + (alvo.lng - origem.lng) * suave
            ]);
            if (t < 1) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                item.animacao = requestAnimationFrame(passo);
            }
        };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        item.animacao = requestAnimationFrame(passo);
    }

    chaveIcone(carreta) {
        return `${carreta.status}|${carreta.placa}|${carreta.id === this.selecionadaId}`;
    }

    // Só recria o ícone quando status, placa ou seleção mudam.
    atualizarIcones() {
        this.carretas.forEach((carreta) => {
            const item = this.marcadores.get(carreta.id);
            const chave = this.chaveIcone(carreta);
            if (item && item.chaveIcone !== chave) {
                item.marcador.setIcon(this.criarIcone(carreta));
                item.marcador.setZIndexOffset(carreta.id === this.selecionadaId ? 1000 : 0);
                item.chaveIcone = chave;
            }
        });
    }

    // Montado com textContent: a placa é dado do usuário, nunca HTML.
    criarIcone(carreta) {
        const raiz = this.criarElemento('div', `marcador status_${STATUS[carreta.status].classe}`);
        if (carreta.id === this.selecionadaId) {
            raiz.classList.add('marcador_selecionado');
        }
        const placa = this.criarElemento('span', 'placa');
        placa.appendChild(this.criarElemento('span', 'placa__faixa', 'BRASIL'));
        placa.appendChild(this.criarElemento('span', 'placa__texto', carreta.placa));
        raiz.appendChild(placa);
        raiz.appendChild(this.criarElemento('span', 'marcador__haste'));
        raiz.appendChild(this.criarElemento('span', 'marcador__ponto'));
        raiz.title = `${carreta.placa}: ${STATUS[carreta.status].label}`;

        // Ícone de tamanho zero: o CSS posiciona o conteúdo para o centro do ponto cair na coordenada.
        return window.L.divIcon({ html: raiz, className: 'marcador-ancora', iconSize: [0, 0] });
    }

    criarElemento(tag, classe, texto) {
        const el = document.createElement(tag);
        el.className = classe;
        if (texto !== undefined) {
            el.textContent = texto;
        }
        return el;
    }

    centralizar() {
        const alvo = this.carretasFiltradasBase;
        if (!this.mapa || !alvo.length) {
            return;
        }
        if (alvo.length === 1) {
            this.mapa.flyTo([alvo[0].latitude, alvo[0].longitude], ZOOM_UMA_CARRETA, { animate: !movimentoReduzido() });
            return;
        }
        const limites = window.L.latLngBounds(alvo.map((c) => [c.latitude, c.longitude]));
        this.mapa.flyToBounds(limites, {
            paddingTopLeft: [60, 60],
            paddingBottomRight: [60, 60],
            maxZoom: ZOOM_UMA_CARRETA,
            animate: !movimentoReduzido()
        });
    }

    selecionar(id, voar = true) {
        this.selecionadaId = id;
        this.atualizarIcones();
        const item = this.marcadores.get(id);
        if (voar && item && this.mapa) {
            this.mapa.flyTo(item.marcador.getLatLng(), Math.max(this.mapa.getZoom(), ZOOM_UMA_CARRETA), {
                animate: !movimentoReduzido(),
                duration: 0.8
            });
        }
    }

    reler() {
        return this.wiredCarretas ? refreshApex(this.wiredCarretas) : Promise.resolve();
    }

    // ---------- Ações ----------

    handleCentralizar() {
        this.centralizar();
    }

    handleSelecionar(event) {
        this.selecionar(event.currentTarget.dataset.id);
    }

    handleFecharCartao() {
        this.selecionadaId = undefined;
        this.atualizarIcones();
    }

    handleBusca(event) {
        this.busca = event.target.value || '';
        this.desenharMarcadores();
    }

    handleFiltro(event) {
        const status = event.currentTarget.dataset.status;
        this.statusAtivos = this.statusAtivos.includes(status)
            ? this.statusAtivos.filter((s) => s !== status)
            : [...this.statusAtivos, status];
        this.desenharMarcadores();
    }

    handleLimparFiltros() {
        this.statusAtivos = [];
        this.busca = '';
        this.desenharMarcadores();
    }

    handleAbrirViagem(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    async handleSincronizar() {
        this.sincronizando = true;
        try {
            await sincronizarAgora();
            await new Promise((resolve) => {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(resolve, ESPERA_APOS_SINCRONIZAR_MS);
            });
            await this.reler();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Não foi possível atualizar as posições', message: reduceErrors(error), variant: 'error' })
            );
        } finally {
            this.sincronizando = false;
        }
    }

    // ---------- Dados para o template ----------

    get modoFrota() {
        return !this._recordId;
    }

    get classeRaiz() {
        return this.modoFrota ? 'frota' : 'frota frota_registro';
    }

    get carretasFiltradasBase() {
        const termo = this.busca.trim().toLowerCase();
        return this.carretas.filter((c) => {
            const passaStatus = !this.statusAtivos.length || this.statusAtivos.includes(c.status);
            const passaBusca =
                !termo ||
                (c.placa || '').toLowerCase().includes(termo) ||
                (c.destino || '').toLowerCase().includes(termo);
            return passaStatus && passaBusca;
        });
    }

    get carretasFiltradas() {
        return this.carretasFiltradasBase.map((c) => this.montarView(c));
    }

    get selecionada() {
        const carreta = this.carretas.find((c) => c.id === this.selecionadaId);
        return carreta ? this.montarView(carreta) : undefined;
    }

    montarView(c) {
        const info = STATUS[c.status];
        const selecionada = c.id === this.selecionadaId;
        return {
            ...c,
            selecionada: String(selecionada),
            statusLabel: info.label,
            classeItem: `item status_${info.classe}${selecionada ? ' item_selecionado' : ''}`,
            rotuloPlaca: `Placa ${c.placa}`,
            velocidadeNumero: Math.round(c.velocidade || 0),
            velocidadeTexto: `${Math.round(c.velocidade || 0)} km/h`,
            atualizadoTexto: tempoDesde(c.ultimaAtualizacao),
            rotaTexto: c.viagemId ? `${c.origem || 'Origem'} → ${c.destino || 'destino não informado'}` : 'Sem viagem em andamento',
            origemTexto: c.origem || 'Origem',
            destinoTexto: c.destino || 'Destino',
            previsaoTexto: c.previsaoChegada ? FORMATO_PREVISAO.format(new Date(c.previsaoChegada)) : 'Sem previsão'
        };
    }

    get classeCartao() {
        return `cartao status_${STATUS[this.selecionada.status].classe}`;
    }

    get filtros() {
        return Object.entries(STATUS).map(([status, info]) => {
            const ativo = this.statusAtivos.includes(status);
            return {
                status,
                label: info.label,
                total: this.carretas.filter((c) => c.status === status).length,
                pressionado: String(ativo),
                classe: `filtro status_${info.classe}${ativo ? ' filtro_ativo' : ''}`
            };
        });
    }

    get temCarretas() {
        return this.carretas.length > 0;
    }

    get semCarretas() {
        return !this.carregando && !this.temCarretas;
    }

    get semResultadoFiltro() {
        return this.temCarretas && !this.carretasFiltradasBase.length;
    }

    get textoTotal() {
        const total = this.carretas.length;
        return total === 1 ? '1 carreta no mapa' : `${total} carretas no mapa`;
    }

    get classeIconeAtualizar() {
        return this.sincronizando ? 'girando' : '';
    }

    get textoBotaoAtualizar() {
        return this.sincronizando ? 'Atualizando' : 'Atualizar posições';
    }

    get mensagemVazio() {
        return this.modoFrota ? 'Nenhuma carreta enviou posição ainda' : 'Esta carreta ainda não tem posição';
    }

    get dicaVazio() {
        return this.modoFrota
            ? 'Cadastre a carreta com o identificador do dispositivo no Traccar e clique em Atualizar posições.'
            : 'Vincule o pedido a uma viagem com carreta, ou aguarde a primeira posição do Traccar.';
    }

    get textoUltimaLeitura() {
        return this.ultimaLeitura ? `Atualizado às ${this.ultimaLeitura.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}` : '';
    }
}
