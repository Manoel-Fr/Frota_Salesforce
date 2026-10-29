@IsTest
private class FrotaMapaControllerTest {
    @TestSetup
    static void setup() {
        System.runAs(FrotaTestData.gestor()) {
            Carreta__c emRota = FrotaTestData.carretaComPosicao('EMR0T00', Datetime.now().addMinutes(-2), 80);
            Carreta__c parada = FrotaTestData.carretaComPosicao('PAR4D00', Datetime.now().addMinutes(-2), 0);
            Carreta__c semSinal = FrotaTestData.carretaComPosicao('SEM5N00', Datetime.now().addHours(-3), 60);
            Carreta__c inativa = FrotaTestData.carretaComPosicao('INA7V00', Datetime.now(), 50);
            inativa.Ativa__c = false;
            Carreta__c semPosicao = FrotaTestData.carreta('NUN0C00', 'nunca');
            insert new List<Carreta__c>{ emRota, parada, semSinal, inativa, semPosicao };

            Viagem__c concluida = FrotaTestData.viagem(emRota.Id, 'Concluida');
            Viagem__c atual = FrotaTestData.viagem(emRota.Id, 'Em_andamento');
            insert new List<Viagem__c>{ concluida, atual };

            Account cliente = new Account(Name = 'Cliente Teste');
            insert cliente;
            insert new List<Order>{
                FrotaTestData.pedido(cliente.Id, atual.Id),
                FrotaTestData.pedido(cliente.Id, atual.Id),
                FrotaTestData.pedido(cliente.Id, concluida.Id),
                FrotaTestData.pedido(cliente.Id, null)
            };
        }
    }

    private static Map<String, FrotaMapaController.CarretaView> porPlaca(List<FrotaMapaController.CarretaView> views) {
        Map<String, FrotaMapaController.CarretaView> mapa = new Map<String, FrotaMapaController.CarretaView>();
        for (FrotaMapaController.CarretaView view : views) {
            mapa.put(view.placa, view);
        }
        return mapa;
    }

    @IsTest
    static void semRegistroDeveTrazerSoCarretasAtivasComPosicao() {
        System.runAs(FrotaTestData.gestor()) {
            Map<String, FrotaMapaController.CarretaView> views = porPlaca(FrotaMapaController.getCarretas(null));

            Assert.areEqual(new Set<String>{ 'EMR0T00', 'PAR4D00', 'SEM5N00' }, views.keySet());
            Assert.areEqual('EM_ROTA', views.get('EMR0T00').status);
            Assert.areEqual('PARADA', views.get('PAR4D00').status);
            Assert.areEqual('SEM_SINAL', views.get('SEM5N00').status, 'Velocidade antiga não vale: sem sinal há 3 h');
        }
    }

    @IsTest
    static void deveTrazerSoAViagemEmAndamentoComSeusPedidos() {
        System.runAs(FrotaTestData.gestor()) {
            FrotaMapaController.CarretaView view = porPlaca(FrotaMapaController.getCarretas(null)).get('EMR0T00');
            Viagem__c atual = [SELECT Id, Name FROM Viagem__c WHERE Status__c = 'Em_andamento'];

            Assert.areEqual(atual.Id, view.viagemId);
            Assert.areEqual(atual.Name, view.viagemNumero);
            Assert.areEqual('Curitiba/PR', view.destino);
            Assert.areEqual(2, view.quantidadePedidos, 'Pedido da viagem concluída não conta');
            Assert.isNull(porPlaca(FrotaMapaController.getCarretas(null)).get('PAR4D00').viagemId);
        }
    }

    @IsTest
    static void naPaginaDoPedidoDeveTrazerSoACarretaDaViagem() {
        System.runAs(FrotaTestData.gestor()) {
            Order pedido = [SELECT Id FROM Order WHERE Viagem__r.Status__c = 'Em_andamento' LIMIT 1];

            List<FrotaMapaController.CarretaView> views = FrotaMapaController.getCarretas(pedido.Id);

            Assert.areEqual(1, views.size());
            Assert.areEqual('EMR0T00', views[0].placa);
        }
    }

    @IsTest
    static void pedidoSemViagemDeveVoltarVazio() {
        System.runAs(FrotaTestData.gestor()) {
            Order pedido = [SELECT Id FROM Order WHERE Viagem__c = null LIMIT 1];

            Assert.areEqual(0, FrotaMapaController.getCarretas(pedido.Id).size());
        }
    }

    @IsTest
    static void naPaginaDaViagemOuDaCarretaDeveFiltrar() {
        System.runAs(FrotaTestData.gestor()) {
            Viagem__c viagem = [SELECT Id, Carreta__c FROM Viagem__c WHERE Status__c = 'Concluida'];
            Carreta__c parada = [SELECT Id FROM Carreta__c WHERE Name = 'PAR4D00'];
            Carreta__c inativa = [SELECT Id FROM Carreta__c WHERE Name = 'INA7V00'];

            Assert.areEqual(viagem.Carreta__c, FrotaMapaController.getCarretas(viagem.Id)[0].id);
            Assert.areEqual(parada.Id, FrotaMapaController.getCarretas(parada.Id)[0].id);
            Assert.areEqual(0, FrotaMapaController.getCarretas(inativa.Id).size(), 'Carreta inativa não aparece nem na própria página');
        }
    }

    @IsTest
    static void outroObjetoDeveMostrarAFrotaToda() {
        System.runAs(FrotaTestData.gestor()) {
            Account cliente = [SELECT Id FROM Account LIMIT 1];

            Assert.areEqual(3, FrotaMapaController.getCarretas(cliente.Id).size());
        }
    }

    @IsTest
    static void statusDeveRespeitarLimitesDeSinalEVelocidade() {
        System.runAs(FrotaTestData.gestor()) {
            Datetime limite = Datetime.now().addMinutes(-FrotaMapaController.MINUTOS_SEM_SINAL);
            Decimal minima = FrotaMapaController.VELOCIDADE_MINIMA_EM_ROTA;

            Assert.areEqual('SEM_SINAL', FrotaMapaController.calcularStatus(null, 50, limite));
            Assert.areEqual('SEM_SINAL', FrotaMapaController.calcularStatus(limite.addSeconds(-1), 50, limite));
            Assert.areEqual('EM_ROTA', FrotaMapaController.calcularStatus(limite, minima, limite));
            Assert.areEqual('PARADA', FrotaMapaController.calcularStatus(limite, minima - 0.1, limite));
        }
    }

    @IsTest
    static void sincronizarAgoraDeveEnfileirarJob() {
        System.runAs(FrotaTestData.gestor()) {
            Test.setMock(HttpCalloutMock.class, new TraccarHttpMock('[]', '[]'));

            Test.startTest();
            Id jobId = FrotaMapaController.sincronizarAgora();
            Test.stopTest();

            Assert.isNotNull(jobId);
            Assert.areEqual('FrotaSyncJob', [SELECT ApexClass.Name FROM AsyncApexJob WHERE Id = :jobId].ApexClass.Name);
        }
    }
}
