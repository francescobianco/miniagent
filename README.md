# miniagent

`miniagent` configura un VPS Linux con Claude Code e OpenAI Codex. Quando entri via SSH compare un menu per scegliere quale coding agent avviare. Entrambi girano con lo stesso utente del computer da cui lanci il provisioning.

## Requisiti

- Un VPS Ubuntu o Debian raggiungibile via SSH, con accesso iniziale a `root` o a un account con `sudo`.
- Sul computer locale: `ssh`, `ssh-copy-id`, `ssh-keygen`, `base64` e `sshpass`.
- Una chiave SSH locale, oppure la disponibilità a crearne una con `ssh-keygen`.
- Un account per Claude e/o ChatGPT con accesso alla rispettiva esperienza CLI. L'autenticazione si completa dal menu al primo avvio.

## Provisioning rapido

Copia e incolla questo blocco nel terminale locale dalla directory del progetto. Lo script legge `SSH_HOST` e `SSH_PASS` dal file `.env` nella root del progetto. Puoi anche passare l'host come primo argomento per sovrascrivere `SSH_HOST`; se `SSH_PASS` manca, la password viene richiesta in modo nascosto.

```bash
bash provision.sh
```

Lo script crea sul VPS l'utente con il nome del tuo utente locale, installa la tua chiave pubblica in `authorized_keys`, disabilita l'accesso SSH tramite password e configura il menu per ogni accesso interattivo. Se l'utente esiste già, lo riutilizza. Per il login iniziale usa `root` con password o un account abilitato a `sudo` (ti verrà chiesta anche la password di sudo, se serve). Puoi passare l'host e l'utente SSH iniziale come argomenti, per esempio `bash provision.sh IP_O_HOST debian`. Il provisioning non è multiutente: un'istanza e un account per VPS.

Lo script installa entrambe le CLI e apre il menu in una sessione `screen` chiamata `miniagent`. Al primo avvio, scegli un agente e completa il login richiesto nel terminale. Se SSH si disconnette, la sessione continua sul VPS; riconnettendoti, il profilo riattacca la stessa sessione e ritrovi l'agente in esecuzione. L'autenticazione resta nella home dell'utente VPS.

Al termine, collegati con:

```bash
ssh "$USER@IP_O_HOST"
```

## Note

- Selezionando Claude Code, il menu avvia `claude --model haiku`; selezionando Codex, avvia `codex`.
- Il menu compare solo in sessioni SSH interattive. Per non-PTY/scp/rsync il profilo non avvia né menu né `screen`.
- Per staccarti manualmente dalla sessione senza chiudere l'agente premi `Ctrl-A`, poi `D`. Al prossimo SSH la sessione `miniagent` viene riattaccata automaticamente; puoi anche usare `screen -r miniagent`.
- Il provisioning supporta Ubuntu/Debian. Dopo aver installato la chiave pubblica, disabilita l'accesso SSH tramite password.
- L'autenticazione CLI è distinta per ciascun prodotto. Il VPS deve poter raggiungere i relativi servizi di login e inference.
