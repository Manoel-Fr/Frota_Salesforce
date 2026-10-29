@IsTest
public class FrotaTestData {
    /**
     * Usuário atual com o permission set Frota_Gestor. As classes usam user mode (API 68), então os testes
     * rodam com esse permission set para provar que ele basta para o fluxo.
     */
    public static User gestor() {
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Frota_Gestor' LIMIT 1].Id;
        Id userId = UserInfo.getUserId();
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId] == 0) {
            insert as system new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
        }
        return new User(Id = userId);
    }

    public static Carreta__c carreta(String placa, String identificador) {
        return new Carreta__c(Name = placa, Identificador_Traccar__c = identificador, Ativa__c = true);
    }

    public static Carreta__c carretaComPosicao(String placa, Datetime ultimaAtualizacao, Decimal velocidade) {
        Carreta__c carreta = carreta(placa, placa.toLowerCase());
        carreta.Ultima_Posicao__Latitude__s = -23.55;
        carreta.Ultima_Posicao__Longitude__s = -46.63;
        carreta.Ultima_Atualizacao__c = ultimaAtualizacao;
        carreta.Velocidade__c = velocidade;
        return carreta;
    }

    public static Viagem__c viagem(Id carretaId, String status) {
        return new Viagem__c(Carreta__c = carretaId, Status__c = status, Origem__c = 'São Paulo/SP', Destino__c = 'Curitiba/PR');
    }

    public static Order pedido(Id accountId, Id viagemId) {
        return new Order(AccountId = accountId, Viagem__c = viagemId, EffectiveDate = Date.today(), Status = 'Draft');
    }
}
