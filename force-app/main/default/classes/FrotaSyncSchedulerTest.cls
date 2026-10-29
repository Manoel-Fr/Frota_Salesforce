@IsTest
private class FrotaSyncSchedulerTest {
    private static Integer jobsAgendados() {
        String filtro = FrotaSyncScheduler.PREFIXO_JOB + '%';
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :filtro];
    }

    @IsTest
    static void deveCriarUmJobPorMinutoDoIntervalo() {
        System.runAs(FrotaTestData.gestor()) {
            List<Id> ids = FrotaSyncScheduler.agendar(5);

            Assert.areEqual(12, ids.size());
            Assert.areEqual(12, jobsAgendados());
            CronTrigger primeiro = [SELECT CronExpression FROM CronTrigger WHERE CronJobDetail.Name = 'Frota Sync :05'];
            Assert.areEqual('0 5 * * * ?', primeiro.CronExpression);
        }
    }

    @IsTest
    static void reagendarDeveSubstituirOsJobsAnteriores() {
        System.runAs(FrotaTestData.gestor()) {
            FrotaSyncScheduler.agendar(5);
            FrotaSyncScheduler.agendar(15);

            Assert.areEqual(4, jobsAgendados(), 'Não pode sobrar job do agendamento anterior');
        }
    }

    @IsTest
    static void deveRecusarIntervaloInvalido() {
        System.runAs(FrotaTestData.gestor()) {
            for (Integer invalido : new List<Integer>{ null, 0, 1, 7, 45, 90 }) {
                try {
                    FrotaSyncScheduler.agendar(invalido);
                    Assert.fail('Intervalo ' + invalido + ' deveria ser recusado');
                } catch (IllegalArgumentException e) {
                    Assert.isTrue(e.getMessage().contains('divisor de 60'));
                }
            }
            Assert.areEqual(0, jobsAgendados());
        }
    }

    @IsTest
    static void cancelarDeveRemoverTodosOsJobs() {
        System.runAs(FrotaTestData.gestor()) {
            FrotaSyncScheduler.agendar(10);

            Assert.areEqual(6, FrotaSyncScheduler.cancelar());
            Assert.areEqual(0, jobsAgendados());
        }
    }

    @IsTest
    static void execucaoAgendadaDeveEnfileirarSincronizacao() {
        System.runAs(FrotaTestData.gestor()) {
            insert FrotaTestData.carreta('ABC1D23', 'celular-manoel');
            Test.setMock(HttpCalloutMock.class, new TraccarHttpMock(
                '[' + TraccarHttpMock.device(7, 'celular-manoel') + ']',
                '[' + TraccarHttpMock.position(7, -23.5, -46.6, 0, '2026-10-29T13:05:12Z') + ']'
            ));

            Test.startTest();
            new FrotaSyncScheduler().execute(null);
            Test.stopTest();

            Assert.isNotNull([SELECT Ultima_Atualizacao__c FROM Carreta__c].Ultima_Atualizacao__c);
        }
    }
}
