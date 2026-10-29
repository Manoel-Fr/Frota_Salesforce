/**
 * Cliente HTTP da API REST do Traccar. Só faz o callout e o parse; regra de negócio fica no FrotaSyncService.
 * Autenticação via Named Credential "Traccar" (token Bearer na External Credential).
 */
public with sharing class TraccarClient {
    private static final String BASE_URL = 'callout:Traccar';
    private static final Integer TIMEOUT_MS = 20000;

    public class TraccarException extends Exception {}

    public class Device {
        public Long id;
        public String uniqueId;
        public String name;
    }

    public class Position {
        public Long deviceId;
        public Decimal latitude;
        public Decimal longitude;
        /** Velocidade em nós, como o Traccar envia. */
        public Decimal speed;
        /** ISO 8601 com fuso, ex.: 2026-10-29T13:05:12.000+00:00 */
        public String fixTime;
    }

    public List<Device> getDevices() {
        return (List<Device>) JSON.deserialize(get('/api/devices'), List<Device>.class);
    }

    /** Última posição de cada dispositivo visível para o usuário do token. */
    public List<Position> getPositions() {
        return (List<Position>) JSON.deserialize(get('/api/positions'), List<Position>.class);
    }

    private String get(String path) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + path);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new TraccarException('Traccar respondeu HTTP ' + res.getStatusCode() + ' em ' + path);
        }
        return res.getBody();
    }
}
