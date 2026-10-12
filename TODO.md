# Stato e prossimi passi di miniagent

## Obiettivo

Preparare un singolo VPS per usare Claude Code con Haiku oppure OpenAI Codex da una connessione SSH. Il VPS usa lo stesso nome utente del computer locale; non vengono configurate chiavi API. Al primo avvio di ciascuna CLI si completa il login interattivo del relativo account.

## Stato del VPS

- Sistema: Debian 13, architettura x86_64.
- Spazio: disco root da 9,7 GB; dopo la pulizia risultano circa 4,8 GB liberi.
- Docker e il progetto Packbase sono stati rimossi su richiesta. Sono stati rimossi container, immagini, volumi, repository e chiave APT Docker, pacchetti Docker e `/opt/packbase` con i relativi dati.
- Packbase era un registry self-hosted per pacchetti Zig: importava repository Git e distribuiva tarball compatibili con `zig fetch`.
- Le porte web 80/443 non sono più servite dal vecchio progetto Packbase/Caddy.
- Il file `.env` locale contiene `SSH_HOST` e `SSH_PASS`; è ignorato da Git. Non inserire credenziali in questo documento.

## Provisioning implementato

- `provision.sh` legge host e password da `.env`, riusa l'utente esistente e la chiave SSH già autorizzata, e può riprendere un'installazione interrotta.
- Installa Node.js 22, Claude Code e Codex sotto il prefisso npm dell'utente quando necessario; verifica entrambe le CLI prima di completare.
- Aggiunge la chiave pubblica all'utente VPS e disabilita il login SSH tramite password dopo aver verificato la configurazione di `sshd`.
- Installa `screen` e configura il menu `miniagent` per le sessioni SSH interattive.
- Verifiche eseguite: `claude --version` riporta `2.1.296`; `codex --version` riporta `0.162.1`.
- Il test SSH interattivo ha mostrato il menu e l'opzione `q` ha chiuso correttamente la sessione.

## Sessione persistente

Il profilo `/home/francesco/.bash_profile` avvia:

```bash
screen -RR miniagent /usr/local/bin/miniagent-menu
```

Il controllo `STY` impedisce di avviare Screen ricorsivamente. Se Screen non riesce a partire, il login ricade su una shell Bash. Quando SSH si interrompe, Screen mantiene il coding agent in esecuzione; il successivo login si riattacca alla sessione chiamata `miniagent`.

Per staccarsi manualmente senza terminare l'agente: `Ctrl-A`, poi `D`. Per vedere le sessioni: `screen -ls`; per riattaccarsi manualmente: `screen -r miniagent`.

## Prossimi passi

- Collegarsi con la chiave SSH a `francesco@<SSH_HOST>`, scegliere Claude Code oppure Codex e completare il login richiesto dalla CLI.
- Provare la continuità reale: avviare un agente, staccarsi con `Ctrl-A`, `D` oppure interrompere SSH, poi riconnettersi e verificare che la sessione riprenda.
- Durante il test è comparso un avviso di Screen relativo alle direttive `deflogin` e `bind ... login` in `/etc/screenrc`. Non ha impedito l'avvio del menu; valutare se correggere la configurazione globale per rimuovere l'avviso.
- Il VPS ha circa 847 MiB di RAM e nessuno swap. L'installazione npm congiunta iniziale è stata terminata dal kernel per memoria insufficiente; il provisioning ora installa/verifica i componenti separatamente e riusa i pacchetti già presenti.

## File del repository

- `provision.sh`: bootstrap SSH, installazione agenti, menu e avvio persistente con Screen.
- `README.md`: requisiti e istruzioni rapide per il provisioning e l'accesso.
- `.env`: configurazione locale `SSH_HOST`/`SSH_PASS`, esclusa dal repository.
