/**
 * Busca no Traccar a última posição de todos os dispositivos e grava nas carretas.
 * Sem retry próprio: se falhar, o job fica como Failed em Apex Jobs e a próxima execução agendada tenta de novo.
 */
public with sharing class FrotaSyncJob implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext context) {
        // Os dois callouts vêm antes de qualquer DML (evita "uncommitted work pending").
        TraccarClient client = new TraccarClient();
        List<TraccarClient.Device> devices = client.getDevices();
        List<TraccarClient.Position> positions = client.getPositions();
        FrotaSyncService.aplicarPosicoes(devices, positions);
    }
}
