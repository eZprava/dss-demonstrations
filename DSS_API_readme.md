# **Návod k Použití DSS API Docker Image**

Tento dokument poskytuje kompletní návod k sestavení a spuštění Docker image obsahujícího DSS API pro validaci elektronicky podepsaných dokumentů. Součástí je i popis použití API, včetně specifického endpointu pro validaci PDF/A.

## **1\. Úvod**

Tento projekt poskytuje Docker kontejner pro snadné nasazení a provozování [DSS (Digital Signature Services)](https://www.google.com/search?q=https://ec.europa.eu/digital-building-blocks/wikis/display/DIGITAL/Digital%2BSignature%2BService%2B-%2BDSS) demoverze webové aplikace. Image je navržen tak, aby byl jednoduchý, efektivní a funkční.

**Klíčové vlastnosti:**

* **Dvoufázový build:** Zajišťuje malou velikost výsledného image.  
* **Služby:** Obsahuje webový server **Tomcat** a reverzní proxy **Nginx** pro HTTPS.  
* **Zabezpečení:** Automaticky generuje self-signed SSL certifikát nebo používá Let's Encrypt.  
* **Persistentní data:** Používá Docker volume pro ukládání certifikátů, logů a SSH klíčů.  
* **Snadná konfigurace:** Možnost nastavení pomocí proměnných prostředí.

## **2\. Předpoklady**

Před zahájením se ujistěte, že máte nainstalovaný a spuštěný **Docker**.

## **3\. Sestavení Docker Image**

Pro sestavení image postupujte následovně:

1. **Umístění souborů:** Ujistěte se, že všechny soubory (Dockerfile, build.sh, install.sh, entrypoint.sh, healthcheck.sh) jsou ve stejném adresáři.  
2. **Spuštění buildu:** V terminálu se přesuňte do adresáře se soubory a spusťte následující příkaz:  
   ```bash
   docker build -t dss-api .
   ```

   Tento proces může trvat několik minut, protože stahuje potřebné závislosti a kompiluje aplikaci.

## **4\. Spuštění Docker Kontejneru**

Po úspěšném sestavení image můžete spustit kontejner několika způsoby podle potřeb zabezpečení.

### **A. Standardní spuštění (self-signed certifikát)**

Pro spuštění kontejneru s automaticky generovaným self-signed certifikátem:

```bash
docker run -d -p 8443:8443 -p 8080:80 -p 2222:22 \
  --name dss-container \
  -v dss-data:/vol \
  dss-api
```

### **B. Spuštění s Let's Encrypt (doporučeno pro produkci)**

Pro použití skutečného SSL certifikátu od Let's Encrypt je nutné:

1. **Vlastnit doménu** pointující na váš server
2. **Otevřít porty 80 a 443** pro ACME challenge a HTTPS provoz
3. **Nastavit proměnnou prostředí LEDN** s názvem vaší domény

```bash
docker run -d -p 443:8443 -p 80:80 -p 2222:22 \
  --name dss-container \
  -e LEDN=dss.vasedomena.cz \
  -v dss-data:/vol \
  dss-api
```

**Důležité poznámky pro Let's Encrypt:**
- Kontejner automaticky požádá o certifikát při prvním spuštění
- Email pro registraci se automaticky nastaví jako `admin@[vasedomena]`
- Certifikát se automaticky obnovuje každých 12 hodin
- Port 80 je potřebný pro ACME challenge verifikaci
- HTTPS bude dostupné na standardním portu 443

### **C. Pokročilá konfigurace s vlastním hostname a IP**

Při sestavování image můžete nastavit proměnné prostředí pro generování SSL certifikátu na míru:

```bash
docker build --build-arg HOSTNAME=dss.mojedomena.cz --build-arg HOSTIP=192.168.1.10 -t dss-api .
```

**Vysvětlení parametrů:**

* `-d`: Spustí kontejner na pozadí  
* `-p 8443:8443` nebo `-p 443:8443`: Mapuje HTTPS port kontejneru na hostitelský stroj  
* `-p 8080:80` nebo `-p 80:80`: Mapuje HTTP port (pro Let's Encrypt je nutný port 80)  
* `-p 2222:22`: Mapuje SSH port 22 kontejneru na port 2222  
* `--name dss-container`: Pojmenuje kontejner pro snazší správu  
* `-v dss-data:/vol`: Vytvoří a připojí pojmenovaný volume pro persistentní data  
* `-e LEDN=domena.cz`: Nastavuje doménu pro Let's Encrypt certifikát

## **5\. SSL Certifikáty - Možnosti Konfigurace**

Kontejner podporuje tři způsoby konfigurace SSL certifikátů:

### **A. Self-signed certifikát (výchozí)**
- Automaticky se generuje při sestavení image
- Vhodné pro testování a vývoj
- Vyžaduje ignorování varování o nedůvěryhodném certifikátu

### **B. Let's Encrypt certifikát**
- Nastavte proměnnou prostředí `LEDN` s vaší doménou
- Automatické získání a obnovování certifikátu
- Doporučeno pro produkční nasazení
- Vyžaduje platnou doménu a přístup z internetu

### **C. Vlastní certifikát**
Po spuštění kontejneru můžete nahradit automaticky generované soubory vlastními:
```bash
# Zkopírování vlastních certifikátů do volume
docker cp your-cert.crt dss-container:/vol/servercert/server.crt
docker cp your-cert.key dss-container:/vol/servercert/server.key

# Restart kontejneru pro načtení nových certifikátů
docker restart dss-container
```

## **6\. Použití DSS API pro Validaci**

API poskytuje RESTful endpointy pro validaci dokumentů. Komunikace probíhá přes HTTPS na portu 8443 (self-signed) nebo 443 (Let's Encrypt).

### **A. Standardní validace podpisu**

Pro validaci elektronického podpisu v dokumentu (např. PDF, ASiC) se používá endpoint `/services/rest/validation/validateSignature`.

**Metoda:** POST  
**URL:** `https://localhost:8443/services/rest/validation/validateSignature` (self-signed)  
**URL:** `https://dss.vasedomena.cz/services/rest/validation/validateSignature` (Let's Encrypt)  
**Tělo požadavku:** multipart/form-data  

**Parametry:**
- `signedDocument`: Soubor, který chcete validovat
- `originalDocuments` (volitelné): Původní soubory, pokud je podpis oddělený
- `policy` (volitelné): Validační politika

**Příklad použití curl (self-signed):**
```bash
curl -k -X POST https://localhost:8443/services/rest/validation/validateSignature \
  -F "signedDocument=@/cesta/k/vasemu/podepsanemu/dokumentu.pdf"
```

**Příklad použití curl (Let's Encrypt):**
```bash
curl -X POST https://dss.vasedomena.cz/services/rest/validation/validateSignature \
  -F "signedDocument=@/cesta/k/vasemu/podepsanemu/dokumentu.pdf"
```

**Odpověď (příklad):**
```json
{
  "valid": true,
  "simpleReport": {
    "validationTime": "2023-10-27T10:00:00Z",
    "indication": "TOTAL_PASSED",
    "subIndication": null,
    "signatureOrTimestamp": [
      {
        "id": "Signature-1",
        "indication": "TOTAL_PASSED"
      }
    ]
  },
  "detailedReport": {
  }
}
```

### **B. Validace podpisu a shody s PDF/A**

Pro současnou validaci podpisu a ověření, že dokument splňuje standard PDF/A, byl přidán speciální endpoint.

**Metoda:** POST  
**URL:** `https://localhost:8443/services/rest/validation/validateSigPdfA` (self-signed)  
**URL:** `https://dss.vasedomena.cz/services/rest/validation/validateSigPdfA` (Let's Encrypt)  
**Tělo požadavku:** multipart/form-data  

**Parametry:**
- `signedDocument`: PDF soubor k validaci

**Příklad použití curl:**
```bash
curl -k -X POST https://localhost:8443/services/rest/validation/validateSigPdfA \
  -F "signedDocument=@/cesta/k/vasemu/pdfa/dokumentu.pdf"
```

**Odpověď (příklad):**
```json
{
  "valid": true,
  "simpleReport": { },
  "detailedReport": { },
  "pdfAValidation": {
    "isCompliant": true,
    "standard": "PDF/A-1b",
    "messages": [
      "Validation successful."
    ]
  }
}
```

## **7\. Trvalá Data (Volume)**

Kontejner využívá volume v cestě `/vol` pro ukládání dat, která mají přetrvat i po jeho zastavení.

**Struktura adresáře /vol:**
- `/vol/servercert`: Obsahuje SSL certifikát (`server.crt`) a privátní klíč (`server.key`). Pro Let's Encrypt jsou certifikáty uloženy v `/etc/letsencrypt/`  
- `/vol/logs`: Adresář pro logy jednotlivých služeb (Nginx, Tomcat, Supervisor, SSH, Certbot)  
- `/vol/sshaccess`: Obsahuje SSH klíče (`id_rsa` a `id_rsa.pub`) pro přístup k kontejneru

## **8\. Přístup a Logy**

### **SSH Přístup**

Do kontejneru se můžete připojit pomocí SSH pro účely správy a ladění:

```bash
ssh -p 2222 root@localhost
```

Pro přihlášení budete potřebovat privátní klíč, který najdete v připojeném volume: `dss-data/_data/sshaccess/id_rsa`.

### **Sledování logů**

Logy aplikace a služeb můžete sledovat přímo v kontejneru nebo v připojeném volume:

```bash
# Logy Tomcat
docker exec -it dss-container tail -f /vol/logs/tomcat/catalina.out

# Logy Nginx
docker exec -it dss-container tail -f /vol/logs/nginx/error.log

# Logy Let's Encrypt (pouze při použití LEDN)
docker exec -it dss-container tail -f /vol/logs/certbot/certbot.log
```

## **9\. Troubleshooting**

### **Let's Encrypt problémy**

Pokud se certifikát nepodaří získat:
1. **Ověřte DNS:** Doména musí pointovat na váš server
2. **Ověřte firewall:** Porty 80 a 443 musí být otevřené
3. **Zkontrolujte logy:** `docker exec -it dss-container tail -f /vol/logs/certbot/certbot.log`
4. **Testovací režim:** Pro testování můžete přidat `--staging` do certbot příkazu

### **SSL problémy**

- **Self-signed varování:** Normální pro self-signed certifikáty, použijte `-k` v curl
- **Certifikát nenalezen:** Zkontrolujte `/vol/servercert/` nebo `/etc/letsencrypt/`
- **Nginx chyby:** Zkontrolujte `/vol/logs/nginx/error.log`

### **Obecné problémy**

- **Kontejner se nestartuije:** Zkontrolujte `docker logs dss-container`
- **API neodpovídá:** Ověřte, že Tomcat běží pomocí healthcheck: `docker exec dss-container /healthcheck.sh`
- **Port konflikty:** Změňte mapování portů v docker run příkazu

## **10\. Bezpečnostní Doporučení**

1. **Produkční nasazení:** Vždy používejte Let's Encrypt nebo vlastní důvěryhodné certifikáty
2. **SSH klíče:** Změňte výchozí SSH klíče v `/vol/sshaccess/`  
3. **Firewall:** Omezte přístup pouze na potřebné porty
4. **Updates:** Pravidelně aktualizujte Docker image
5. **Monitoring:** Nastavte monitoring zdraví kontejneru pomocí health check

## **11\. Příklady Použití**

### **Rychlé testování (self-signed)**
```bash
docker run -d -p 8443:8443 --name dss-test -v dss-test:/vol dss-api
curl -k -X POST https://localhost:8443/services/rest/validation/validateSignature \
  -F "signedDocument=@test.pdf"
```

### **Produkční nasazení (Let's Encrypt)**
```bash
docker run -d -p 443:8443 -p 80:80 \
  --name dss-prod \
  -e LEDN=dss.firma.cz \
  -v dss-prod:/vol \
  --restart unless-stopped \
  dss-api
```

### **Nasazení s reverse proxy (doporučeno)**
Pokud už používáte reverse proxy (nginx, traefik), můžete kontejner spustit pouze s HTTP:
```bash
docker run -d -p 8080:8080 \
  --name dss-internal \
  -v dss-internal:/vol \
  dss-api
```