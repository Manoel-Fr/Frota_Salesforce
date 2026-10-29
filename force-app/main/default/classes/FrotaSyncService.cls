/**
 * Aplica as posições do Traccar nas carretas. Grava só a última posição (sem histórico) e
 * ignora posições mais antigas que a já gravada, então reprocessar a mesma resposta é seguro.
 */
public with sharing class FrotaSyncService {
    @TestVisible
    private static final Decimal NOS_PARA_KMH = 1.852;

    public static Integer aplicarPosicoes(List<TraccarClient.Device> devices, List<TraccarClient.Position> positions) {
        Map<Long, String> identificadorPorDevice = new Map<Long, String>();
        for (TraccarClient.Device device : devices ?? new List<TraccarClient.Device>()) {
            if (device.id != null && String.isNotBlank(device.uniqueId)) {
                identificadorPorDevice.put(device.id, device.uniqueId.toLowerCase());
            }
        }

        Map<String, TraccarClient.Position> posicaoPorIdentificador = new Map<String, TraccarClient.Position>();
        for (TraccarClient.Position posicao : positions ?? new List<TraccarClient.Position>()) {
            String identificador = identificadorPorDevice.get(posicao.deviceId);
            if (identificador != null && posicao.latitude != null && posicao.longitude != null) {
                posicaoPorIdentificador.put(identificador, posicao);
            }
        }
        if (posicaoPorIdentificador.isEmpty()) {
            return 0;
        }

        List<Carreta__c> paraAtualizar = new List<Carreta__c>();
        for (Carreta__c carreta : [
            SELECT Id, Identificador_Traccar__c, Ultima_Atualizacao__c
            FROM Carreta__c
            WHERE Identificador_Traccar__c IN :posicaoPorIdentificador.keySet()
            WITH USER_MODE
        ]) {
            TraccarClient.Position posicao = posicaoPorIdentificador.get(carreta.Identificador_Traccar__c.toLowerCase());
            Datetime dataPosicao = parseDataTraccar(posicao.fixTime);
            if (dataPosicao == null || (carreta.Ultima_Atualizacao__c != null && dataPosicao <= carreta.Ultima_Atualizacao__c)) {
                continue;
            }
            paraAtualizar.add(new Carreta__c(
                Id = carreta.Id,
                Ultima_Posicao__Latitude__s = posicao.latitude,
                Ultima_Posicao__Longitude__s = posicao.longitude,
                Velocidade__c = ((posicao.speed ?? 0) * NOS_PARA_KMH).setScale(1),
                Ultima_Atualizacao__c = dataPosicao
            ));
        }

        Integer atualizadas = 0;
        for (Database.SaveResult resultado : Database.update(paraAtualizar, false, AccessLevel.USER_MODE)) {
            if (resultado.isSuccess()) {
                atualizadas++;
            } else {
                System.debug(LoggingLevel.ERROR, 'Falha ao atualizar carreta ' + resultado.getId() + ': ' + resultado.getErrors());
            }
        }
        return atualizadas;
    }

    /** Converte o ISO 8601 do Traccar (com fuso "+00:00", "-0300" ou "Z") para Datetime em GMT. */
    @TestVisible
    private static Datetime parseDataTraccar(String valor) {
        if (String.isBlank(valor) || valor.length() < 19) {
            return null;
        }
        try {
            Datetime base = Datetime.newInstanceGmt(
                Integer.valueOf(valor.substring(0, 4)),
                Integer.valueOf(valor.substring(5, 7)),
                Integer.valueOf(valor.substring(8, 10)),
                Integer.valueOf(valor.substring(11, 13)),
                Integer.valueOf(valor.substring(14, 16)),
                Integer.valueOf(valor.substring(17, 19))
            );
            String resto = valor.substring(19);
            Integer posSinal = Math.max(resto.lastIndexOf('+'), resto.lastIndexOf('-'));
            if (posSinal < 0) {
                return base;
            }
            String fuso = resto.substring(posSinal + 1).remove(':');
            Integer minutos = Integer.valueOf(fuso.left(2)) * 60 + (fuso.length() >= 4 ? Integer.valueOf(fuso.substring(2, 4)) : 0);
            Integer sinal = resto.substring(posSinal, posSinal + 1) == '-' ? -1 : 1;
            return base.addMinutes(-sinal * minutos);
        } catch (TypeException e) {
            return null;
        } catch (StringException e) {
            return null;
        }
    }
}
