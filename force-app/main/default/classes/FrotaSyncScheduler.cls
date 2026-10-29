/**
 * Agenda a sincronização com o Traccar. O cron do Salesforce roda no máximo uma vez por hora por job,
 * então criamos um job por minuto do intervalo (ex.: a cada 5 min = 12 jobs).
 * Uso (Apex anônimo): FrotaSyncScheduler.agendar(5);  /  FrotaSyncScheduler.cancelar();
 */
public with sharing class FrotaSyncScheduler implements Schedulable {
    @TestVisible
    private static final String PREFIXO_JOB = 'Frota Sync :';
    private static final Integer INTERVALO_MINIMO = 2;

    public void execute(SchedulableContext context) {
        System.enqueueJob(new FrotaSyncJob());
    }

    public static List<Id> agendar(Integer intervaloMinutos) {
        if (intervaloMinutos == null || intervaloMinutos < INTERVALO_MINIMO || Math.mod(60, intervaloMinutos) != 0) {
            throw new IllegalArgumentException(
                'Intervalo inválido: use um divisor de 60 a partir de ' + INTERVALO_MINIMO + ' (2, 3, 4, 5, 6, 10, 12, 15, 20, 30 ou 60).'
            );
        }
        cancelar();
        List<Id> jobIds = new List<Id>();
        for (Integer minuto = 0; minuto < 60; minuto += intervaloMinutos) {
            jobIds.add(System.schedule(
                PREFIXO_JOB + String.valueOf(minuto).leftPad(2, '0'),
                '0 ' + minuto + ' * * * ?',
                new FrotaSyncScheduler()
            ));
        }
        return jobIds;
    }

    public static Integer cancelar() {
        String filtro = PREFIXO_JOB + '%';
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :filtro];
        for (CronTrigger job : jobs) {
            System.abortJob(job.Id);
        }
        return jobs.size();
    }
}
