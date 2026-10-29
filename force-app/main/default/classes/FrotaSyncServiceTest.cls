@IsTest
private class FrotaSyncServiceTest {
    private static TraccarClient.Device device(Long id, String uniqueId) {
        TraccarClient.Device device = new TraccarClient.Device();
        device.id = id;
        device.uniqueId = uniqueId;
        return device;
    }

    private static TraccarClient.Position position(Long deviceId, Decimal speedNos, String fixTime) {
        TraccarClient.Position position = new TraccarClient.Position();
        position.deviceId = deviceId;
        position.latitude = -25.4284;
        position.longitude = -49.2733;
        position.speed = speedNos;
        position.fixTime = fixTime;
        return position;
    }

    @IsTest
    static void deveGravarPosicaoConvertendoNosParaKmhEFusoParaGmt() {
        System.runAs(FrotaTestData.gestor()) {
            insert FrotaTestData.carreta('ABC1D23', 'Celular-Manoel');

            Test.startTest();
            Integer atualizadas = FrotaSyncService.aplicarPosicoes(
                new List<TraccarClient.Device>{ device(7, 'celular-manoel') },
                new List<TraccarClient.Position>{ position(7, 10, '2026-10-29T10:05:12.000-03:00') }
            );
            Test.stopTest();

            Carreta__c carreta = [SELECT Ultima_Posicao__Latitude__s, Ultima_Posicao__Longitude__s, Velocidade__c, Ultima_Atualizacao__c FROM Carreta__c];
            Assert.areEqual(1, atualizadas);
            Assert.areEqual(-25.4284, carreta.Ultima_Posicao__Latitude__s);
            Assert.areEqual(-49.2733, carreta.Ultima_Posicao__Longitude__s);
            Assert.areEqual(18.5, carreta.Velocidade__c, '10 nós = 18,52 km/h, arredondado para 18,5');
            Assert.areEqual(Datetime.newInstanceGmt(2026, 10, 29, 13, 5, 12), carreta.Ultima_Atualizacao__c, 'Identificador deve casar sem diferenciar maiúsculas');
        }
    }

    @IsTest
    static void naoDeveSobrescreverComPosicaoMaisAntigaOuIgual() {
        System.runAs(FrotaTestData.gestor()) {
            Carreta__c carreta = FrotaTestData.carretaComPosicao('ABC1D23', Datetime.newInstanceGmt(2026, 10, 29, 13, 0, 0), 50);
            insert carreta;

            Integer atualizadas = FrotaSyncService.aplicarPosicoes(
                new List<TraccarClient.Device>{ device(7, 'abc1d23') },
                new List<TraccarClient.Position>{ position(7, 0, '2026-10-29T13:00:00.000+00:00') }
            );

            Assert.areEqual(0, atualizadas);
            Assert.areEqual(50, [SELECT Velocidade__c FROM Carreta__c].Velocidade__c, 'Posição igual ou mais antiga não pode alterar a carreta');
        }
    }

    @IsTest
    static void deveIgnorarDispositivoSemCarretaEPosicaoSemCoordenada() {
        System.runAs(FrotaTestData.gestor()) {
            insert FrotaTestData.carreta('ABC1D23', 'abc1d23');
            TraccarClient.Position semCoordenada = position(8, 5, '2026-10-29T13:00:00Z');
            semCoordenada.latitude = null;

            Integer atualizadas = FrotaSyncService.aplicarPosicoes(
                new List<TraccarClient.Device>{ device(7, 'outro-celular'), device(8, 'abc1d23') },
                new List<TraccarClient.Position>{ position(7, 5, '2026-10-29T13:00:00Z'), semCoordenada, position(99, 5, '2026-10-29T13:00:00Z') }
            );

            Assert.areEqual(0, atualizadas);
            Assert.isNull([SELECT Ultima_Atualizacao__c FROM Carreta__c].Ultima_Atualizacao__c);
        }
    }

    @IsTest
    static void deveAceitarListasNulasOuVazias() {
        System.runAs(FrotaTestData.gestor()) {
            Assert.areEqual(0, FrotaSyncService.aplicarPosicoes(null, null));
            Assert.areEqual(0, FrotaSyncService.aplicarPosicoes(new List<TraccarClient.Device>(), new List<TraccarClient.Position>()));
        }
    }

    @IsTest
    static void deveAtualizarFrotaGrandeEmLote() {
        System.runAs(FrotaTestData.gestor()) {
            List<Carreta__c> carretas = new List<Carreta__c>();
            List<TraccarClient.Device> devices = new List<TraccarClient.Device>();
            List<TraccarClient.Position> positions = new List<TraccarClient.Position>();
            for (Integer i = 0; i < 200; i++) {
                carretas.add(FrotaTestData.carreta('PLACA' + i, 'disp-' + i));
                devices.add(device(i, 'disp-' + i));
                positions.add(position(i, 20, '2026-10-29T13:00:00.000+00:00'));
            }
            insert carretas;

            Test.startTest();
            Integer atualizadas = FrotaSyncService.aplicarPosicoes(devices, positions);
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(200, atualizadas);
            Assert.areEqual(1, queries, 'Deve haver uma única query, independente do tamanho da frota');
            Assert.areEqual(200, [SELECT COUNT() FROM Carreta__c WHERE Velocidade__c = 37.0]);
        }
    }

    @IsTest
    static void deveConverterFormatosDeDataDoTraccar() {
        System.runAs(FrotaTestData.gestor()) {
            Datetime esperado = Datetime.newInstanceGmt(2026, 10, 29, 13, 5, 12);
            Assert.areEqual(esperado, FrotaSyncService.parseDataTraccar('2026-10-29T13:05:12.000+00:00'));
            Assert.areEqual(esperado, FrotaSyncService.parseDataTraccar('2026-10-29T10:05:12.000-03:00'));
            Assert.areEqual(esperado, FrotaSyncService.parseDataTraccar('2026-10-29T10:05:12-0300'));
            Assert.areEqual(esperado, FrotaSyncService.parseDataTraccar('2026-10-29T13:05:12Z'));
            Assert.areEqual(esperado, FrotaSyncService.parseDataTraccar('2026-10-29T15:35:12.000+02:30'));
            Assert.isNull(FrotaSyncService.parseDataTraccar(null));
            Assert.isNull(FrotaSyncService.parseDataTraccar('ontem'));
            Assert.isNull(FrotaSyncService.parseDataTraccar('2026-XX-29T13:05:12Z'));
        }
    }
}
