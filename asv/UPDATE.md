# Manutenção do fork ASV

Base: `asv/upstream.json`. O submódulo `hbb_common` foi incluído como fonte normal, no commit registrado, para que o clone e o arquivo correspondente não dependam de gitlinks externos. Seus arquivos não foram modificados.

## Mapa dos arquivos efetivamente utilizados

| Arquivo | Uso / alteração |
|---|---|
| `src/common.rs` | Inicialização da identidade interna, mapas de opções impostas e consulta de atualização |
| `src/platform/windows.rs` | Retorna servidor/chave incorporados no caminho que antes interpretava o nome do arquivo; recusa instalação enquanto o serviço oficial está ativo |
| `src/flutter.rs` | Nome visível exportado ao runner nativo e usado na busca de janela existente |
| `src/tray.rs` | Nome visível no tooltip da bandeja; ID de instância permanece interno |
| `src/flutter_ffi.rs` | Reaplica configuração ASV na instância da DLL Flutter, inclusive se houver custom config recebida |
| `flutter/lib/common.dart` | Nome visível das janelas; logo real em `assets/logo*.png` e ícone em `assets/icon.png` |
| `flutter/lib/main.dart` | Título da aplicação |
| `flutter/lib/desktop/widgets/tabbar_widget.dart` | Nome que antes estava fixo em RustDesk na barra de abas |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | Sobre, créditos preservados e link para fonte correspondente |
| `flutter/windows/runner/Runner.rc` | ProductName/FileDescription e ícone compilado do runner |
| `Cargo.toml`, `libs/portable/Cargo.toml` | Metadados dos executáveis; copyright original preservado |
| `libs/portable/src/main.rs` | Reconhece sufixo Setup.exe e abre instalador original |
| `asv/prepare_brand.py` | Copia recursos reais antes de compilar e registra hashes |
| `res/icon.ico` | Recurso Rust em `build.rs` e recurso do empacotador em `libs/portable/build.rs` |
| `res/tray-icon.ico` | Fallback compilado da bandeja em `src/tray.rs` |
| `flutter/windows/runner/resources/app_icon.ico` | Ícone PE nativo do runner, barra de tarefas e instalador |
| `flutter/assets/icon.png`, `icon.ico` | Ícone de interface/bandeja e atalho/Registro na instalação customizada |
| `flutter/assets/logo.png`, `logo_light.png`, `logo_dark.png` | Logotipo efetivamente carregado por `_Logo` no Flutter atual |

Os SVGs em `res/logo*.svg` são do caminho legado; substituí-los isoladamente não personaliza a interface Flutter. `flutter/assets/icon.svg` permanece apenas como fallback se o PNG não puder ser carregado; o teste exige o PNG ASV instalado.

## Ao trocar a base

1. Escolha uma release oficial estável; registre SHA e SHA do submódulo em `upstream.json`.
2. Compare com `changes.patch`, reaplicando somente os pontos ASV. Não faça substituição global de RustDesk: protocolos, caminhos de DLL, créditos e bibliotecas têm outros usos.
3. Revise a ordem de inicialização tanto do processo nativo como da DLL Flutter, os mapas OVERWRITE e a precedência de configuração por nome de arquivo.
4. Compare as etapas Windows de `.github/workflows/flutter-build.yml` e a geração de ponte da nova base. Os workflows ASV foram derivados da versão fixada e limitados a x64; não chamam o build oficial de todas as plataformas nem publicam em releases oficiais.
5. Atualize o gerador de marca se os caminhos consumidos mudarem. Não altere executáveis assinados; faça alterações no fonte/recursos antes de compilar e assine depois, se houver certificado empresarial.
6. Rode o workflow e conclua a matriz manual descrita no README. Verifique atualização ASV→ASV, persistência do ID e produto anterior MSI/EXE.
7. Disponibilize instalador, fonte correspondente, licença, avisos e hashes de forma durável. Atualize `changes.patch` e a lista de caminhos alterados.

## Superfície de regressão

Mudam identidade e configuração iniciais de todos os processos deste fork, resolução de servidor/chave e verificação do serviço anterior no Windows, seleção de marca/títulos na interface, metadados e reconhecimento do instalador no empacotador. Esses caminhos precisam mudar para atender à identidade ASV sem configuração manual e sem comandos Windows inseguros com espaços. O serviço continua usando a implementação original, porém com outro nome e perfil de configuração. Captura, entrada, transporte, autenticação, transferência e protocolos não foram reimplementados. O código legado Sciter não é alvo de entrega.

### Correção da instalação interativa

Superfície alterada: `src/flutter_ffi.rs::install_install_me` passa a devolver falhas da instalação Windows ao Future do Flutter, sem usar o caminho que registrava o erro e encerrava o processo com código zero. `flutter/lib/desktop/pages/install_page.dart::install` aguarda esse resultado, exibe a causa e restaura os controles para tentar novamente. A assinatura Dart continua `Future<void>`; a ponte precisa ser regenerada. A instalação nativa, o protocolo e a instalação silenciosa permanecem no caminho anterior. A regressão é verificada clicando no botão com o serviço oficial ativo e repetindo após parar o serviço de teste.
