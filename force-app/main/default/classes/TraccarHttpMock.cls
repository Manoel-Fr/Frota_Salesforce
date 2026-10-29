/** Mock do Traccar para testes: responde /api/devices e /api/positions com corpos configuráveis. */
@IsTest
public class TraccarHttpMock implements HttpCalloutMock {
    private final Integer statusCode;
    private final String devicesBody;
    private final String positionsBody;

    public TraccarHttpMock(String devicesBody, String positionsBody) {
        this(200, devicesBody, positionsBody);
    }

    public TraccarHttpMock(Integer statusCode, String devicesBody, String positionsBody) {
        this.statusCode = statusCode;
        this.devicesBody = devicesBody;
        this.positionsBody = positionsBody;
    }

    public HttpResponse respond(HttpRequest req) {
        Assert.isTrue(req.getEndpoint().startsWith('callout:Traccar/api/'), 'Endpoint inesperado: ' + req.getEndpoint());
        Assert.areEqual('GET', req.getMethod());
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(req.getEndpoint().endsWith('/api/devices') ? devicesBody : positionsBody);
        return res;
    }

    public static String device(Long id, String uniqueId) {
        return '{"id":' + id + ',"name":"Dispositivo ' + id + '","uniqueId":"' + uniqueId + '","status":"online"}';
    }

    public static String position(Long deviceId, Decimal lat, Decimal lng, Decimal speedNos, String fixTime) {
        return '{"id":' + (deviceId * 10) + ',"deviceId":' + deviceId + ',"latitude":' + lat + ',"longitude":' + lng +
            ',"speed":' + speedNos + ',"fixTime":"' + fixTime + '","valid":true,"attributes":{"batteryLevel":80}}';
    }
}
