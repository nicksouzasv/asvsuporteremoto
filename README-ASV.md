# ASV Suporte Remoto

Cliente Windows x64 derivado do [RustDesk oficial 1.5.0](https://github.com/rustdesk/rustdesk/releases/tag/1.5.0), commit `fada664df7a294d1d1a9ca3e7cd3637069122f17`. Código integral e `hbb_common` incluídos neste repositório; não é preciso compilar Windows no Mac.

## Plano técnico

1. Fixar fonte oficial e submódulo, identificar recursos Flutter e Windows.
2. Aplicar identidade oficial ASV e incorporar servidor/chave nos caminhos usados pela interface e serviço.
3. Compilar e empacotar no Windows 2022 pelo Actions, usando o empacotador e a instalação de serviço originais.
4. Validar instalação, identidade persistente, opções efetivas, registro no servidor e recursos; concluir homologação em dois PCs.

## Compilar

Abra **Actions → ASV Windows x64 → Run workflow**. O processo exige os recursos reais em `asv/brand/` e usa as versões de Flutter, Rust, LLVM e vcpkg do workflow oficial fixado. Não exige secrets de assinatura nem configurações no nome do executável.

O artefato `ASV-Suporte-Remoto-Windows-x64` contém:

- `ASV-Suporte-Remoto-Setup.exe`;
- `ASV-Suporte-Remoto-source.tar.gz`, licença e avisos;
- `validation-windows.json`, ícone extraído e hashes dos arquivos.

Um artefato de uma execução com falha pode conter um instalador não homologado. Só distribuir depois de todos os testes automáticos passarem e a homologação manual ser concluída. O instalador não é assinado digitalmente; SmartScreen/UAC podem exigir confirmação. A instalação do serviço precisa de administrador, conforme o projeto original. Isso não exige digitar servidor/chave após instalar.

Para implantação por ferramenta administrativa, execute `ASV-Suporte-Remoto-Setup.exe --silent-install` com privilégios elevados. O instalador interativo também permanece disponível. Não há senha permanente pré-configurada: acesso sem configuração de rede não significa autorização irrestrita de acesso remoto. As formas de consentimento/autenticação originais permanecem.

## Revalidar um instalador existente

O workflow **ASV Validate Existing Installer** recebe o ID de uma execução de compilação e testa o mesmo EXE em outro Windows limpo, sem alterar o binário. O pacote validado inclui a procedência do código, a revisão do script de teste e os hashes. Isso permite corrigir ou ampliar a validação sem recompilar ou modificar executáveis prontos.

O primeiro instalador foi compilado no commit `e4b6d7ba654bbac4bc64bfe893d1976fcbe6aafe`. A primeira execução interrompeu os testes ao tentar ler saída de um comando de alteração de opção, que não retorna texto. A correção foi apenas no teste. A execução de validação [39314173633](https://github.com/nicksouzasv/asvsuporteremoto/actions/runs/39314173633) concluiu com sucesso sobre o EXE original. Seu fonte correspondente permanece o do commit compilado, indicado no arquivo de procedência e na tela Sobre.

## Identificadores e configurações

Nome visível na interface e metadados: **ASV Suporte Remoto**. Serviço, pasta, executável instalado e atalhos usam `ASV-Suporte-Remoto`. A validação de nomes do instalador oficial exige `[a-zA-Z0-9-]+`; preservá-la evita alterar dezenas de comandos de serviço e Registro para suportar espaços.

- Servidor ID: `rustdesk.asv.com.br`.
- Chave pública: `vZmmsfIrplKLZdZB4FoaD8o39dSPJaV58RY4SW0ipxc=`.
- Relay: descoberto pelo servidor de rendezvous; não foi inventado endereço adicional.
- Serviço automático separado, instalação em `%ProgramFiles%\ASV-Suporte-Remoto`.
- Configurações por usuário em `%APPDATA%\ASV-Suporte-Remoto\config`; serviço usa o perfil da conta de serviço.

As opções de servidor/chave são impostas em memória a cada inicialização do processo e serviço. Portanto, podem não aparecer gravadas no TOML: seu valor efetivo vem do executável. O teste usa `--option` por IPC, tenta alterá-las, reinicia o serviço e verifica novamente. Nome de arquivo e `custom.txt` não substituem a configuração ASV. A rede fica oculta na interface. Atualizações automáticas e sua consulta periódica são desativadas; distribuir novas versões ASV após recompilar e homologar.

## RustDesk anterior

A política padrão é **instalação separada**, sem importar automaticamente credenciais, chave privada, lista de pares ou ID anterior. Serviço, pastas, atalhos e Registro da ASV não substituem os do RustDesk oficial. Uma nova instalação ASV recebe sua própria identidade; atualizações ASV reutilizam sua configuração e devem manter o ID. Não prometa igualdade do ID com a instalação oficial: verifique no equipamento e no servidor.

A instalação ASV é recusada enquanto o serviço oficial `RustDesk` estiver em execução. O código original pode gerar o mesmo ID a partir do MAC e usa o identificador da máquina; separar pastas não garante IDs diferentes nem evita conflito de chaves no mesmo servidor. Pare o serviço oficial por uma via administrativa independente antes de instalar a ASV. Não mantenha dois serviços de acesso remoto ativos na implantação definitiva: podem disputar captura, entrada, porta de acesso direto e integração de impressora/tela virtual. Em uma migração, pare o serviço antigo, instale e teste a ASV por uma via administrativa independente; depois remova o RustDesk antigo pelo mecanismo original, preservando backup sob controle da empresa. Não desinstale silenciosamente a única ferramenta que mantém uma sessão de suporte ativa. MSI oficial anterior e EXE ASV são produtos separados; não fazemos conversão MSI→EXE nem migração automática destrutiva.

O teste CI usa Windows limpo. O cenário com RustDesk anterior exige VM específica, inclusive aplicação de políticas e conta de serviço da empresa.

## Licença e fonte

`LICENCE` e créditos originais preservados. `asv/NOTICE.txt` registra as modificações. A compilação adiciona à tela Sobre um link para o commit exato deste repositório público. O arquivo de fonte correspondente é criado **depois** da geração da ponte e aplicação da marca, inclui `hbb_common`, scripts e recursos e acompanha tanto a distribuição quanto a pasta instalada.

Distribua fonte e instalador juntos, mantenha o commit disponível aos destinatários e retenha o arquivo correspondente além do prazo de expiração dos artefatos do Actions. Não publique só o EXE. As dependências externas continuam sob suas próprias licenças. Confira os termos de redistribuição dos recursos ASV e das dependências ao publicar.

## Validação e limites

O script `asv/validate-windows.ps1` instala um **serviço real de acesso remoto** e deve ser executado somente em runner/VM descartável. Ele testa PE x64, serviço automático, inicialização da janela, logo/ícones instalados, opções e ID após reinício de serviço, portas TCP e confirmação de registro de chave pelo rendezvous (`key_confirmed = true`). Não publica configurações ou logs que possam conter chaves privadas.

Ainda é necessário homologar manualmente: uma sessão autenticada entre dois PCs com a chave fornecida, conexão direta e relay, reinicialização completa do Windows, marca na bandeja/barra de tarefas/instalador/atalhos, temas claro/escuro e coexistência/migração. Registro de chave confirmado e portas abertas não equivalem a uma sessão remota autenticada nem comprovam a chave do servidor ponta a ponta.

## Atualizações futuras

Consulte `asv/UPDATE.md` e `asv/changes.patch`. O código do protocolo, captura, autenticação e implementação de serviço não foi substituído. Os workflows continuam usando alguns downloads externos mutáveis do upstream (engine Flutter e drivers); o commit do RustDesk está fixado, mas isso não torna toda a cadeia de dependências reproduzível byte a byte. Revise e fixe hashes desses downloads antes de exigir builds herméticos.

## Correção do botão de instalação

A instalação interativa Flutter passa a aguardar o resultado nativo. Se o serviço RustDesk original estiver ativo, se a permissão de administrador for cancelada ou se houver outro erro, o motivo aparece em uma caixa de diálogo e o botão é liberado para nova tentativa. A janela só encerra após sucesso. O serviço original não é parado automaticamente. A instalação silenciosa continua usando o caminho original.

`asv/validate-install-button.ps1` exercita o botão real pela acessibilidade nativa MSAA em Windows descartável, com um instalador oficial RustDesk 1.5.0 de hash fixado como cenário de conflito. Confere a mensagem visível, a preservação do serviço anterior e a nova tentativa pelo mesmo botão após parar explicitamente o serviço de teste. O workflow de validação independente aceita a opção `interactive` para repetir esse teste sobre um EXE existente.


A correção foi compilada no commit `731150ebd2e8267d11ae5cab931823af81a3b279` e validada na execução [39341601704](https://github.com/nicksouzasv/asvsuporteremoto/actions/runs/39341601704), com 24 verificações gerais e 6 registros do cenário interativo aprovados. O teste clicou no botão com o RustDesk oficial ativo, confirmou o aviso e a preservação do serviço, depois parou explicitamente esse serviço no runner descartável e instalou ASV pelo mesmo botão. O EXE tem SHA-256 `61592408b4177d3900d6f5b6a5d0d48bdd097e58a4115780c905650621d45f40`. Os testes atualizados são identificados separadamente no arquivo de procedência; o EXE e o fonte embarcado não foram alterados após a compilação.

Na migração real, use acesso local ou uma via administrativa independente para parar o serviço RustDesk original e colocar sua inicialização em Manual antes de instalar ASV. Após confirmar o acesso pelo ASV, avalie remover a instalação original. O instalador ASV não altera automaticamente esse serviço; se o original permanecer automático, ele pode voltar no próximo reinício. O UAC com usuário comum, a reinicialização completa e uma sessão autenticada entre dois PCs ainda exigem aceitação no ambiente real.
