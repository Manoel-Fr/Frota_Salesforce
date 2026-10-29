@IsTest
private class FrotaSyncJobTest {
    @IsTest
    static void deveBuscarNoTraccarEGravarNasCarretas() {
        System.runAs(FrotaTestData.gestor()) {
            insert FrotaTestData.carreta('ABC1D23', 'celular-manoel');
            Test.setMock(HttpCalloutMock.class, new TraccarHttpMock(
                '[' + TraccarHttpMock.device(7, 'celular-manoel') + ']',
                '[' + TraccarHttpMock.position(7, -23.5, -46.6, 0, '2026-10-29T13:05:12.000+00:00') + ']'
            ));

            Test.startTest();
            System.enqueueJob(new FrotaSyncJob());
            Test.stopTest();

            Carreta__c carreta = [SELECT Ultima_Posicao__Latitude__s, Velocidade__c, Ultima_Atualizacao__c FROM Carreta__c];
            Assert.areEqual(-23.5, carreta.Ultima_Posicao__Latitude__s);
            Assert.areEqual(0, carreta.Velocidade__c);
            Assert.areEqual(Datetime.newInstanceGmt(2026, 10, 29, 13, 5, 12), carreta.Ultima_Atualizacao__c);
        }
    }

    @IsTest
    static void naoDeveAlterarCarretasQuandoTraccarFalha() {
        System.runAs(FrotaTestData.gestor()) {
            insert FrotaTestData.carreta('ABC1D23', 'celular-manoel');
            Test.setMock(HttpCalloutMock.class, new TraccarHttpMock(503, 'Service Unavailable', 'Service Unavailable'));

            try {
                Test.startTest();
                System.enqueueJob(new FrotaSyncJob());
                Test.stopTest();
                Assert.fail('A falha do Traccar deve marcar o job como falho');
            } catch (TraccarClient.TraccarException e) {
                Assert.isTrue(e.getMessage().contains('503'));
            }
            Assert.isNull([SELECT Ultima_Atualizacao__c FROM Carreta__c].Ultima_Atualizacao__c);
        }
    }
}
