# Galp Pluma Inteligente → iOS: protocolo Bluetooth

Fontes:
- `Galp+Pluma_1.1_APKPure.xapk` (pacote `com.galp.smartbottle`, versão 1.1), analisado a 2026-11-19.
- Duas capturas PacketLogger a 15/09/2026 com a garrafa dele: `~/15.09.2026 11.50.07.pklg` e `~/15.09.2026 12.11.12.pklg`.

Uso pessoal, para ler uma garrafa que é tua. Não contém código, imagens nem textos da Galp.

---

## 1. O que a app Galp faz (e o que não faz)

A app Galp Pluma é feita em OutSystems (Cordova). O Bluetooth está em `BluetoothConnectorV2_Plug.controller.js`, com o plugin `cordova-plugin-ble-central`.

A app **não sabe o protocolo**. Pede tudo ao servidor da Galp:
- `GetDeviceIds` → UUID do serviço e da característica.
- `GetDeviceCommand` / `GetCommandBuffer2("GET_BUFFER", deviceId)` → os bytes a enviar, em base64.
- `GetBuffer` / `DeviceReading` → recebe as respostas em bruto e devolve `GasLevel`, `MaxWeigth`, alerta de temperatura, etc.

Na app Galp, o nome Bluetooth da garrafa vem do servidor (`DeviceName`), depois de ler o NFC (`NFC_Code`) ou o QR.

**QR code:** a app Galp fica com o texto depois de `id=` (sem distinguir maiúsculas), ou com o texto todo se não houver `id=` (`ParingQRCodeOrNFC_SmartBottle_NEW`, ação `ReadQRCode`). **Nome Bluetooth:** as garrafas anunciam-se como `Pluma--<número>` (exemplo `Pluma--xxxxxxxxxxx`, teste de 19/11). O QR da garrafa (`https://pluma.galp.com/SmartBottle.aspx?id=08G93`) não contém esse número; é o servidor da Galp que liga os dois. Por isso a app iOS ignora o QR: procura por Bluetooth os nomes começados por `Pluma--` e mostra-os do mais próximo para o mais longe.

## Protocolo da Pluma (capturado a 19/11 numa leitura real da app Galp)

Garrafa `Pluma--xxxxxxxxxxx` (`XX:XX:XX:XX:XX:XX`).

- Serviços: `180A` (informação do aparelho) e `D973F2E0-B19E-11E2-9E96-0800200C9A66`.
- Característica de comando: **`D973F2E1-B19E-11E2-9E96-0800200C9A66`** (escrita com resposta + notificações). Há também `D973F2E3-…`, não usada.

### Tramas

`comando(1) + hora Unix(4, big-endian) + checksum(1)`, com **checksum = (soma dos outros bytes + 0xAA) & 0xFF**. (Confirmado em todos os comandos e na resposta.)

A app faz: escreve `0x55` + hora (acerta o relógio), escreve `0x03` + hora (pede leitura), recebe a resposta e desliga.

Exemplo real (21:34:10 UTC = `0x6AFF6B52`):
```
→ 55 6A FF 6B 52 25     (acertar relógio)
→ 03 6A FF 6B 52 D3     (ler)
← 03 01 00 00 00 00 00 8D 18 16 69   (resposta)
```

### Resposta `03 01 <8 bytes> checksum`

Payload = `00 00 00 00 00 8D 18 16`:
- **byte 6 = `0x18` = 24 → temperatura em °C.** Confirmado (a app Galp mostrava 24ºC).
- **byte 7 = `0x16` = 22 → nível de gás ~%.** Provisório: a app Galp mostrava 21% (e "3 de 12 Kg"). Falta confirmar a fórmula exata com leituras a níveis diferentes.
- byte 5 = `0x8D` = 141: por identificar (talvez peso bruto ×10 = 14,1 kg).
- bytes 0-4 = 0: por identificar (contador/histórico?).

Para acertar a fórmula do %, a app guarda cada resposta em bruto e deixa escrever o % que a app Galp mostrou (ecrã Leituras, export CSV).

---

## 2. GATT (das capturas)

As capturas não incluem a descoberta de serviços (o iPhone já tinha a cache), por isso **os UUIDs não são conhecidos**. Só os handles:

| Handle | Uso |
|---|---|
| `0x0004`, `0x0009`, `0x000C` | CCCD: a app escreve `01 00` nos três (liga notificações) |
| `0x0006` | Escrita **sem resposta** (Write Command): é para aqui que vão os pedidos |
| `0x0008` | Notificações: chegam aqui as respostas |

A app iOS descobre tudo sozinha: liga as notificações em todas as características que as têm e escreve na que tem `writeWithoutResponse`.

Endereço da garrafa desse aparelho (aleatório): `XX:XX:XX:XX:XX:XX`.

## 3. Tramas

Pedido (telemóvel → garrafa):

```
55 AA  LEN  CMD  [dados…]        LEN = 1 + nº de bytes de dados
```

Resposta (garrafa → telemóvel):

```
AA 55  LEN  CMD  [dados…]        LEN = 1 + nº de bytes de dados
```

Algumas notificações trazem 3 bytes a mais depois da trama (nos registos do 0x05). Não fazem parte da trama e são ignorados.

Não há checksum.

## 4. Sequência da app Galp (igual nas duas capturas)

| # | Pedido | Resposta | O que parece ser |
|---|---|---|---|
| 1 | `55 AA 01 1C` | `AA 55 0F 22` + 14 bytes | Texto ASCII. 1.ª captura: `696969`; 2.ª: tudo zeros. **Por confirmar** |
| 2 | `55 AA 01 12` | `AA 55 06 12 "2.4.."` | Versão do firmware (ASCII) |
| 3 | `55 AA 01 0B` | `AA 55 03 0C xx xx` e `AA 55 03 0D xx xx` | Duas medidas de 16 bits. 0x0C: `CE B6` → `E8 F3`; 0x0D: `E8 80` nas duas. **Por confirmar** |
| 4 | `55 AA 01 0E` | `AA 55 02 0E xx` | Um byte: `0x24` (36) → `0x20` (32). **Candidato ao nível de gás em %**, por confirmar |
| 5 | `55 AA 0F 02` + `yyyyMMddHHmmss` (ASCII) | `AA 55 01 02` | Acerta o relógio da garrafa (hora local) |
| 6 | `55 AA 01 1E` | `AA 55 02 24 01` | Um byte, sempre `01`. **Por confirmar** |
| 7 | `55 AA 01 05` | N × `AA 55 13 05 …` e no fim `AA 55 01 06` | Descarrega o registo de eventos |

Entre a 1.ª e a 2.ª captura passaram 21 minutos (à hora de almoço).

### Registo de eventos (0x05)

Cada registo: `"01_"` + data `yyyyMMddHHmmss` (ASCII) + 1 byte de tipo (0, 1 ou 2).

- 1.ª captura: 49 registos, de 03/10/2025 a 23/05/2026 (as datas não vêm por ordem).
- 2.ª captura: nenhum registo. **O registo parece apagar-se depois de lido.** Se a app iOS o descarregar, a app Galp pode deixar de receber esses eventos. Por isso a app iOS só o faz quando se pede.
- Um evento tipo 2 é quase sempre seguido, 3 horas e 2 segundos depois, por um tipo 0 ou 1.

## 5. Para fechar o significado

Basta uma leitura com as duas apps: ler na app Galp (anotar o %), e logo a seguir ler com a app iOS. A app iOS guarda os valores brutos de cada leitura e deixa partilhá-los, para fazer a correspondência.
