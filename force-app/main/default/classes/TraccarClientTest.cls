@IsTest
private class TraccarClientTest {
    @IsTest
    static void deveLerDispositivosEPosicoesIgnorandoCamposExtras() {
        Test.setMock(HttpCalloutMock.class, new TraccarHttpMock(
            '[' + TraccarHttpMock.device(7, 'celular-manoel') + ']',
            '[' + TraccarHttpMock.position(7, -23.5, -46.6, 10, '2026-10-29T13:05:12.000+00:00') + ']'
        ));

        Test.startTest();
        TraccarClient client = new TraccarClient();
        List<TraccarClient.Device> devices = client.getDevices();
        List<TraccarClient.Position> positions = client.getPositions();
        Test.stopTest();

        Assert.areEqual(1, devices.size());
        Assert.areEqual(7, devices[0].id);
        Assert.areEqual('celular-manoel', devices[0].uniqueId);
        Assert.areEqual(1, positions.size());
        Assert.areEqual(7, positions[0].deviceId);
        Assert.areEqual(-23.5, positions[0].latitude);
        Assert.areEqual(10, positions[0].speed);
        Assert.areEqual('2026-10-29T13:05:12.000+00:00', positions[0].fixTime);
    }

    @IsTest
    static void deveLancarExcecaoComStatusQuandoTraccarRecusa() {
        Test.setMock(HttpCalloutMock.class, new TraccarHttpMock(401, 'Unauthorized', 'Unauthorized'));

        Test.startTest();
        try {
            new TraccarClient().getPositions();
            Assert.fail('Deveria lançar TraccarException para HTTP 401');
        } catch (TraccarClient.TraccarException e) {
            Assert.isTrue(e.getMessage().contains('401'), 'Mensagem deve ter o status: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains('/api/positions'), 'Mensagem deve ter o caminho: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
