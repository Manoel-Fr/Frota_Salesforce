/**
 * Dados do LWC frotaMapa. Sem recordId devolve a frota ativa inteira; numa página de Carreta, Viagem ou
 * Pedido (Order) devolve só a carreta daquele registro.
 */
public with sharing class FrotaMapaController {
    /**
     * Celular parado em segundo plano para de enviar posição para poupar bateria, então o silêncio tolerado
     * depende de como a carreta estava na última posição: andando, 15 min já é sinal perdido; parada, 2 h.
     */
    @TestVisible
    private static final Integer MINUTOS_SEM_SINAL_EM_ROTA = 15;
    @TestVisible
    private static final Integer MINUTOS_SEM_SINAL_PARADA = 120;
    @TestVisible
    private static final Decimal VELOCIDADE_MINIMA_EM_ROTA = 5;
    private static final String VIAGEM_EM_ANDAMENTO = 'Em_andamento';
    private static final Integer LIMITE_CARRETAS = 2000;

    public class CarretaView {
        @AuraEnabled public Id id;
        @AuraEnabled public String placa;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public Decimal velocidade;
        @AuraEnabled public Datetime ultimaAtualizacao;
        /** EM_ROTA, PARADA ou SEM_SINAL */
        @AuraEnabled public String status;
        @AuraEnabled public Id viagemId;
        @AuraEnabled public String viagemNumero;
        @AuraEnabled public String origem;
        @AuraEnabled public String destino;
        @AuraEnabled public Datetime previsaoChegada;
        @AuraEnabled public Integer quantidadePedidos;
    }

    @AuraEnabled(cacheable=true)
    public static List<CarretaView> getCarretas(Id recordId) {
        try {
            Set<Id> carretaIds = resolverCarretas(recordId);
            if (carretaIds != null && carretaIds.isEmpty()) {
                return new List<CarretaView>();
            }
            return montarViews(buscarCarretas(carretaIds));
        } catch (Exception e) {
            AuraHandledException erro = new AuraHandledException(e.getMessage());
            erro.setMessage('Não foi possível carregar a frota: ' + e.getMessage());
            throw erro;
        }
    }

    /** Dispara uma sincronização fora do agendamento (botão "Atualizar agora"). */
    @AuraEnabled
    public static Id sincronizarAgora() {
        try {
            return System.enqueueJob(new FrotaSyncJob());
        } catch (Exception e) {
            AuraHandledException erro = new AuraHandledException(e.getMessage());
            erro.setMessage('Não foi possível iniciar a sincronização: ' + e.getMessage());
            throw erro;
        }
    }

    /** null = sem filtro (frota toda); conjunto vazio = registro sem carreta vinculada. */
    private static Set<Id> resolverCarretas(Id recordId) {
        if (recordId == null) {
            return null;
        }
        Set<Id> ids = new Set<Id>();
        SObjectType tipo = recordId.getSObjectType();
        if (tipo == Carreta__c.SObjectType) {
            ids.add(recordId);
        } else if (tipo == Viagem__c.SObjectType) {
            for (Viagem__c viagem : [SELECT Carreta__c FROM Viagem__c WHERE Id = :recordId AND Carreta__c != null WITH USER_MODE]) {
                ids.add(viagem.Carreta__c);
            }
        } else if (tipo == Order.SObjectType) {
            for (Order pedido : [SELECT Viagem__r.Carreta__c FROM Order WHERE Id = :recordId AND Viagem__r.Carreta__c != null WITH USER_MODE]) {
                ids.add(pedido.Viagem__r.Carreta__c);
            }
        } else {
            return null;
        }
        return ids;
    }

    private static List<Carreta__c> buscarCarretas(Set<Id> carretaIds) {
        String filtroIds = carretaIds == null ? '' : ' AND Id IN :carretaIds';
        return Database.queryWithBinds(
            'SELECT Id, Name, Ultima_Posicao__Latitude__s, Ultima_Posicao__Longitude__s, Velocidade__c, Ultima_Atualizacao__c,' +
            ' (SELECT Id, Name, Origem__c, Destino__c, Previsao_Chegada__c FROM Viagens__r' +
            '  WHERE Status__c = :emAndamento ORDER BY CreatedDate DESC LIMIT 1)' +
            ' FROM Carreta__c' +
            ' WHERE Ativa__c = true AND Ultima_Posicao__Latitude__s != null' + filtroIds +
            ' ORDER BY Name LIMIT ' + LIMITE_CARRETAS,
            new Map<String, Object>{ 'carretaIds' => carretaIds, 'emAndamento' => VIAGEM_EM_ANDAMENTO },
            AccessLevel.USER_MODE
        );
    }

    private static List<CarretaView> montarViews(List<Carreta__c> carretas) {
        Set<Id> viagemIds = new Set<Id>();
        for (Carreta__c carreta : carretas) {
            if (!carreta.Viagens__r.isEmpty()) {
                viagemIds.add(carreta.Viagens__r[0].Id);
            }
        }
        Map<Id, Integer> pedidosPorViagem = new Map<Id, Integer>();
        if (!viagemIds.isEmpty()) {
            for (AggregateResult linha : [
                SELECT Viagem__c viagem, COUNT(Id) total
                FROM Order
                WHERE Viagem__c IN :viagemIds
                WITH USER_MODE
                GROUP BY Viagem__c
            ]) {
                pedidosPorViagem.put((Id) linha.get('viagem'), (Integer) linha.get('total'));
            }
        }

        Datetime agora = Datetime.now();
        List<CarretaView> views = new List<CarretaView>();
        for (Carreta__c carreta : carretas) {
            CarretaView view = new CarretaView();
            view.id = carreta.Id;
            view.placa = carreta.Name;
            view.latitude = carreta.Ultima_Posicao__Latitude__s;
            view.longitude = carreta.Ultima_Posicao__Longitude__s;
            view.velocidade = carreta.Velocidade__c ?? 0;
            view.ultimaAtualizacao = carreta.Ultima_Atualizacao__c;
            view.status = calcularStatus(carreta.Ultima_Atualizacao__c, view.velocidade, agora);
            if (!carreta.Viagens__r.isEmpty()) {
                Viagem__c viagem = carreta.Viagens__r[0];
                view.viagemId = viagem.Id;
                view.viagemNumero = viagem.Name;
                view.origem = viagem.Origem__c;
                view.destino = viagem.Destino__c;
                view.previsaoChegada = viagem.Previsao_Chegada__c;
                view.quantidadePedidos = pedidosPorViagem.get(viagem.Id) ?? 0;
            }
            views.add(view);
        }
        return views;
    }

    @TestVisible
    private static String calcularStatus(Datetime ultimaAtualizacao, Decimal velocidade, Datetime agora) {
        if (ultimaAtualizacao == null) {
            return 'SEM_SINAL';
        }
        Boolean emMovimento = velocidade >= VELOCIDADE_MINIMA_EM_ROTA;
        Integer toleranciaMinutos = emMovimento ? MINUTOS_SEM_SINAL_EM_ROTA : MINUTOS_SEM_SINAL_PARADA;
        if (ultimaAtualizacao < agora.addMinutes(-toleranciaMinutos)) {
            return 'SEM_SINAL';
        }
        return emMovimento ? 'EM_ROTA' : 'PARADA';
    }
}
