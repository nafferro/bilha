# Bilha

App de iPhone para ler a garrafa de gás Galp Pluma Inteligente por Bluetooth, sem a app da Galp. O design segue o do [beam](https://github.com/nafferro/beam).

O protocolo está em [PROTOCOLO-BLE.md](PROTOCOLO-BLE.md). Foi tirado da app Android Galp Pluma 1.1 e de duas capturas Bluetooth de 15/09/2026.

> Não é da Galp nem tem nada da Galp. Uso pessoal.

## O que faz

- Várias garrafas: em "Adicionar garrafa" a app procura por Bluetooth as garrafas `Pluma--…` por perto (a mais próxima em primeiro) e tocas na tua. Removes quando quiseres (toque longo na lista, ou no menu da garrafa) e podes dar-lhes um nome, por exemplo "Cozinha".
- **Ler garrafa**: envia os mesmos comandos que a app Galp, guarda a leitura e desliga.
- Mostra o nível de gás. **Ainda é provisório**: é o byte da resposta 0x0E, que deu 36 e 32 nas capturas.
- **Leituras**: lista das leituras. Toca numa para escrever o % que a app Galp mostrou nessa altura. Exporta em CSV.
- **Registo de eventos**: só quando pedes. Parece que a garrafa apaga o registo depois de o enviar.
- **Português ou inglês**: segue o idioma do iPhone; dá para escolher à mão em ⋯ → Idioma (Automático, Português, English), e muda logo, sem reiniciar.
- **Registo Bluetooth**: tudo o que foi enviado e recebido, para partilhar.

## Instalar

```bash
cd pluma-ios && xcodegen generate && open Bilha.xcodeproj
```

Escolhe o iPhone e carrega em Run. A equipa de assinatura já está no `project.yml`.

## Testes

```bash
xcodebuild test -project Bilha.xcodeproj -scheme Bilha -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```
