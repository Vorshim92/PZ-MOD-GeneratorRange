# TimedActions in Project Zomboid Build 42 - Guida Completa

## Indice

1. [Panoramica](#panoramica)
2. [Le due architetture](#le-due-architetture)
3. [Azioni Shared (Networked) - Il nuovo sistema](#azioni-shared-networked)
   - [Struttura base](#struttura-base)
   - [Metodi Client-Side](#metodi-client-side)
   - [Metodi Server-Side](#metodi-server-side)
   - [Metodi di utilita](#metodi-di-utilita)
4. [Flusso completo Client-Server](#flusso-completo-client-server)
5. [Regole critiche per la serializzazione](#regole-critiche-per-la-serializzazione)
6. [Pattern: Azione timed semplice](#pattern-azione-timed-semplice)
7. [Pattern: Azione looped con AnimEvent](#pattern-azione-looped-con-animevent)
8. [Pattern: Azione con aggiornamento progressivo](#pattern-azione-con-aggiornamento-progressivo)
9. [Pattern: Azione senza timeout](#pattern-azione-senza-timeout)
10. [AnimEventEmulator](#animeventemulator)
11. [ISTimedActionQueue - Gestione della coda](#istimedactionqueue)
12. [adjustMaxTime - Penalita automatiche](#adjustmaxtime)
13. [Campi e proprieta della tabella](#campi-e-proprieta-della-tabella)
14. [Differenze Singleplayer vs Multiplayer](#differenze-singleplayer-vs-multiplayer)
15. [Errori comuni e troubleshooting](#errori-comuni-e-troubleshooting)
16. [Riferimenti al codice sorgente](#riferimenti-al-codice-sorgente)

---

## Panoramica

In Build 42, Project Zomboid ha introdotto un sistema **dual client-server** per le timed action.
Il server e' ora **autoritativo**: la logica di gioco critica (consumo item, crafting, danno, ecc.)
viene eseguita sul server, mentre il client gestisce solo animazioni, suoni e UI.

La classe Lua `LuaTimedActionNew` (Java) determina automaticamente quale sistema usare:
- Se la metatabella dell'azione ha un metodo `complete()` -> usa il sistema **NetTimedAction** (shared/networked)
- Se NON ha `complete()` -> usa il vecchio sistema **custom sync** (client-only, legacy)

```java
// LuaTimedActionNew.java - costruttore
if (table.getMetatable().rawget("complete") == null) {
    this.useCustomRemoteTimedActionSync = true;  // Legacy
}
```

---

## Le due architetture

### Azioni Client-Only (Legacy)

- Cartella: `lua/client/TimedActions/`
- NON hanno `complete()`, `serverStart()`, `serverStop()`, `animEvent()`
- Tutta la logica gira sul client
- Usate per: movimento, climbing, grab item, trasferimento inventario
- Esempi: `ISClimbThroughWindow`, `ISInventoryTransferAction`, `ISGrabItemAction`

### Azioni Shared (Networked) - Build 42

- Cartella: `lua/shared/TimedActions/`
- HANNO `complete()` e opzionalmente `serverStart()`, `serverStop()`, `animEvent()`
- La logica di gioco critica gira sul server tramite `complete()`
- Il client gestisce solo animazioni e UI
- Esempi: `ISCraftAction`, `ISEatFoodAction`, `ISChopTreeAction`, `ISReadABook`

---

## Azioni Shared (Networked)

### Struttura base

```lua
ISMyAction = ISBaseTimedAction:derive("ISMyAction")
-- La stringa "ISMyAction" diventa il campo Type usato per la serializzazione.
-- DEVE corrispondere al nome della variabile globale Lua.

function ISMyAction:new(character, item, targetObject)
    -- I NOMI dei parametri (character, item, targetObject) sono CRITICI.
    -- Il sistema di rete li usa come chiavi per serializzare/deserializzare.
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.targetObject = targetObject
    o.maxTime = 100
    return o
end
```

### Metodi Client-Side

Questi metodi vengono eseguiti **solo sul client**.

#### `start()`
Chiamato quando l'azione inizia. Imposta animazioni, suoni, variabili visive.

```lua
function ISMyAction:start()
    self:setActionAnim("Loot")
    self:setOverrideHandModels(self.item, nil, false)
    self.sound = self.character:playSound("MySound")
end
```

#### `update()`
Chiamato ogni tick durante l'esecuzione. Per aggiornamenti visivi e progress bar.

```lua
function ISMyAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
    -- Non mettere logica di gioco qui in multiplayer!
end
```

#### `perform()`
Chiamato quando l'azione completa (il timer client-side e' scaduto e il server ha confermato).
Solo cleanup visivo. In singleplayer, puo' contenere la logica di gioco.

```lua
function ISMyAction:perform()
    -- Cleanup
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISInventoryPage.dirtyUI()

    -- Logica di gioco SOLO in singleplayer
    if not isClient() then
        self:doTheActualWork()
    end

    -- OBBLIGATORIO: chiamare il perform base
    ISBaseTimedAction.perform(self)
end
```

#### `stop()`
Chiamato quando l'azione viene interrotta (il giocatore cammina, invalida, ecc.).

```lua
function ISMyAction:stop()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end
```

#### `isValidStart()`
Validazione prima dell'avvio. Se ritorna `false`, l'azione non parte.

```lua
function ISMyAction:isValidStart()
    if self.character:getMoodles():getMoodleLevel(MoodleType.DEAD) > 0 then
        return false
    end
    return true
end
```

#### `isValid()`
Validazione continua durante l'esecuzione. Se ritorna `false`, l'azione viene interrotta.

```lua
function ISMyAction:isValid()
    -- In multiplayer, gli item possono cambiare reference.
    -- Usa getItemById() per ri-trovare l'item.
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end
    return self.item ~= nil
end
```

#### `waitToStart()`
Se ritorna `true`, l'azione aspetta prima di iniziare (es. il personaggio deve girarsi).

```lua
function ISMyAction:waitToStart()
    self.character:faceThisObject(self.targetObject)
    return true
end
```

#### `getDeltaModifiers(deltas)`
Per modificare il movimento del personaggio durante l'azione.

```lua
function ISMyAction:getDeltaModifiers(deltas)
    deltas:setTurnDelta(0.0)  -- Impedisce di girarsi
end
```

### Metodi Server-Side

Questi metodi vengono eseguiti **solo sul server** (o in singleplayer se non si e' client).

#### `complete()`
Il metodo piu' importante. Contiene la **logica autoritativa** del server.
**DEVE ritornare `true` (successo) o `false` (rifiuto).**

```lua
function ISMyAction:complete()
    -- Tutta la logica di gioco va qui
    self.character:getInventory():Remove(self.item)
    if isServer() then
        sendRemoveItemFromContainer(self.character:getInventory(), self.item)
    end
    return true
end
```

Se `complete()` ritorna `false`, il server manda un pacchetto `Reject` al client
e l'azione viene annullata.

#### `serverStart()`
Chiamato sul server quando l'azione viene accettata. Setup server-side.

```lua
function ISMyAction:serverStart()
    -- Inizializzazione server-side
    -- Ottieni riferimenti a oggetti, valida lato server
    self.serverItem = self.character:getInventory():getItemById(self.item:getID())

    -- Per azioni looped: registra emulazione anim events
    emulateAnimEvent(self.netAction, 1500, "MyEvent", nil)
end
```

#### `serverStop()`
Chiamato sul server quando l'azione viene cancellata (il client ha inviato un Reject).

```lua
function ISMyAction:serverStop()
    -- Cleanup server-side
    -- Applica effetti parziali se necessario
    self.serverItem:syncItemFields()
end
```

#### `animEvent(event, parameter)`
Chiamato dal `AnimEventEmulator` server-side quando un evento animazione emulato si attiva.
Lato client, viene chiamato dal motore di animazione reale.

```lua
function ISMyAction:animEvent(event, parameter)
    if event == "MyEvent" then
        if isServer() then
            -- Logica server-side
            self:applyDamage()
            if self:isDone() then
                self.netAction:forceComplete()  -- Forza completamento
            end
        end
        if isClient() then
            -- Effetti visivi client-side
            self:playHitEffect()
        end
    end
end
```

#### `getDuration()`
Ritorna la durata dell'azione. Il server la usa per calcolare `endTime`.

```lua
function ISMyAction:getDuration()
    return self.maxTime  -- Default di ISBaseTimedAction
end
```

Il valore ritornato viene moltiplicato per 20 lato server (conversione tick -> ms):
```java
// NetTimedAction.java
float duration = ((Double)result.getFirst()).floatValue();
return duration == -1.0F ? -1.0F : duration * 20.0F;
```

Per azioni looped (infinite), ritorna `-1`:
```lua
function ISMyLoopedAction:getDuration()
    return -1  -- Il completamento e' gestito da animEvent/forceComplete
end
```

#### `isUsingTimeout()`
Se ritorna `false`, il server non applica timeout sull'azione. Default: `true`.

```lua
function ISMyAction:isUsingTimeout()
    return false  -- Il server non forzera' il completamento per timeout
end
```

### Metodi di utilita

Metodi ereditati da `ISBaseTimedAction` che puoi chiamare (non sovrascrivere):

| Metodo | Descrizione |
|--------|-------------|
| `self:setActionAnim(animName)` | Imposta l'animazione dell'azione |
| `self:setAnimVariable(key, val)` | Imposta una variabile di animazione |
| `self:setOverrideHandModels(primary, secondary, reset)` | Modelli mani con InventoryItem |
| `self:setOverrideHandModelsString(primary, secondary, reset)` | Modelli mani con stringhe |
| `self:forceComplete()` | Forza il completamento (client-side) |
| `self:forceStop()` | Forza lo stop |
| `self:setTime(time)` | Imposta maxTime |
| `self:setCurrentTime(time)` | Imposta il tempo corrente |
| `self:getJobDelta()` | Ottieni progresso (0.0-1.0) |
| `self:setJobDelta(delta)` | Imposta progresso manualmente |
| `self:resetJobDelta()` | Resetta il progresso |
| `self:beginAddingActions()` | Inizia blocco di azioni annidate (in perform) |
| `self:endAddingActions()` | Fine blocco azioni annidate |
| `self:addAfter(action)` | Aggiunge un'azione dopo questa nella coda |
| `self:overrideWeaponType()` | Override tipo arma per animazione |
| `self:restoreWeaponType()` | Ripristina tipo arma |

---

## Flusso completo Client-Server

```
CLIENT                                       SERVER
======                                       ======

ISTimedActionQueue.add(action)
    |
    v
isValidStart() -> false? ANNULLA
    |
    v
action:begin()
    |
    v
action:create()
    |-> LuaTimedActionNew.new(self, character)
    |-> maxTime = adjustMaxTime(maxTime)    [SOLO client-side!]
    |
    v
character:StartAction(action)
    |
    v
start() [animazioni, suoni]
    |
    |--- [Pacchetto NetTimedAction Request] --->  processServer()
    |                                                |
    |                                                v
    |                                          parse(): ricostruisce azione Lua
    |                                          chiama ISMyAction:new() con args deserializzati
    |                                                |
    |                                                v
    |                                          isConsistent()? NO -> Reject
    |                                                |
    |                                                v
    |                                          ActionManager.start()
    |                                                |
    |                                                v
    |                                          NetTimedAction.start()
    |                                            -> getDuration() [calcola durata]
    |                                            -> setTimeData() [startTime + endTime]
    |                                            -> serverStart() [setup server]
    |                                                |
    |    <--- [Pacchetto Accept + duration] ---      |
    |                                                |
    v                                                v
setWaitForFinished(true)                    ActionManager.update() [ogni tick]
update() [ogni tick, UI]                         |
isValid() [ogni tick]                       endTime raggiunto?
    |                                            |
    |                                            v
    |                                       NetTimedAction.perform()
    |                                            -> complete() [LOGICA DI GIOCO]
    |                                            -> return true/false
    |                                                |
    |    <--- [Pacchetto Done o Reject] ---          |
    |                                                |
    v                                                v
ActionManager.isDone()?                     Azione rimossa dalla lista server
    -> forceComplete()
    -> perform() [cleanup UI]
    |
    v
ISBaseTimedAction.perform()
    -> onCompleted()
    -> avvia prossima azione in coda
```

### Sincronizzazione del tempo

Il server calcola la durata indipendentemente dal client:

```java
// LuaTimedActionNew.java - update()
if (this.getTime() == -1) {
    float duration = ActionManager.getDuration(this.transactionId) / 20.0F;
    if (duration > 0.0F && !ActionManager.isLooped(this.transactionId)) {
        this.table.rawset("maxTime", (double)duration);
        this.setTime((int)duration);
    }
}
```

Il client riceve la durata calcolata dal server e aggiorna il suo timer locale.
Questo garantisce che `adjustMaxTime()` (che gira solo client-side) non causi
desincronizzazione.

---

## Regole critiche per la serializzazione

Il sistema `NetTimedAction` serializza automaticamente i parametri dell'azione leggendo
la firma del metodo `new()`. Queste regole sono **obbligatorie**:

### 1. Il nome dei parametri di `new()` DEVE corrispondere ai campi della tabella

```lua
-- CORRETTO: i parametri si chiamano "character", "item", "amount"
-- e vengono salvati come self.character, self.item, self.amount
function ISMyAction:new(character, item, amount)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.amount = amount
    return o
end

-- SBAGLIATO: il parametro si chiama "itm" ma viene salvato come self.item
function ISMyAction:new(character, itm, amount)
    local o = ISBaseTimedAction.new(self, character)
    o.item = itm  -- Il server cerchera' "itm" nella tabella, non "item"!
    o.amount = amount
    return o
end
```

Come funziona internamente:
```java
// NetTimedAction.java - set()
Prototype itemNew = ((LuaClosure)action.getMetatable().rawget("new")).prototype;
for (int i = 1; i < itemNew.numParams; i++) {
    String paramName = itemNew.locvars[i];       // Nome del parametro: "item"
    Object o = this.action.rawget(paramName);     // Legge self.item dalla tabella
    this.actionArgs.rawset(paramName, o);         // Salva per la serializzazione
}
```

### 2. Il `Type` deve essere il nome della variabile globale Lua

```lua
-- CORRETTO
ISMyAction = ISBaseTimedAction:derive("ISMyAction")

-- SBAGLIATO: Type non corrisponde alla variabile globale
ISMyAction = ISBaseTimedAction:derive("MyCustomAction")
-- Il server cerchera' LuaManager.get("MyCustomAction") e non trovera' nulla
```

### 3. I parametri devono essere serializzabili

Tipi supportati da `PZNetKahluaTableImpl`:
- `IsoPlayer` / `IsoGameCharacter` -> serializzato come `PlayerID`
- `IsoObject` / `IsoGridSquare` -> serializzato per posizione
- `InventoryItem` -> serializzato per ID
- `String`, `Double`, `Boolean` -> serializzati direttamente
- `KahluaTable` -> serializzata ricorsivamente
- `Vehicle` / `BaseVehicle` -> serializzato per ID
- `null` / `nil` -> supportato

Tipi **NON** supportati:
- Funzioni Lua
- Userdata custom
- Riferimenti ciclici

### 4. Il file deve stare in `lua/shared/`

Il server deve poter caricare la classe Lua. Se il file e' in `lua/client/`,
il server non lo vedra' e l'azione fallira' con un errore di deserializzazione.

### 5. Il campo `netAction` viene iniettato automaticamente

Dopo la deserializzazione server-side, il campo `self.netAction` viene impostato
automaticamente al riferimento `NetTimedAction` Java:

```java
// NetTimedAction.java - parse()
this.action.rawset("netAction", this);
```

Questo e' il riferimento da usare con `emulateAnimEvent()` e `forceComplete()` server-side.

---

## Pattern: Azione timed semplice

Azione con durata fissa che esegue la logica al completamento.

```lua
ISSimpleAction = ISBaseTimedAction:derive("ISSimpleAction")

function ISSimpleAction:isValid()
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end
    return self.item ~= nil
end

function ISSimpleAction:isValidStart()
    return self.item ~= nil and self.character:getInventory():contains(self.item)
end

function ISSimpleAction:start()
    self:setActionAnim("Loot")
    self:setOverrideHandModels(self.item, nil, false)
end

function ISSimpleAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISSimpleAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISSimpleAction:perform()
    -- Solo cleanup client-side
    ISInventoryPage.dirtyUI()

    -- Singleplayer: esegui la logica qui
    if not isClient() then
        self:doWork()
    end

    ISBaseTimedAction.perform(self)
end

-- SERVER-SIDE: logica autoritativa
function ISSimpleAction:complete()
    self:doWork()
    return true
end

function ISSimpleAction:doWork()
    -- La logica di gioco condivisa
    self.character:getInventory():Remove(self.item)
    if isServer() then
        sendRemoveItemFromContainer(self.character:getInventory(), self.item)
    end
end

function ISSimpleAction:getDuration()
    return self.maxTime
end

function ISSimpleAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.maxTime = 150
    return o
end
```

Utilizzo:
```lua
local action = ISSimpleAction:new(playerObj, someItem)
ISTimedActionQueue.add(action)
```

---

## Pattern: Azione looped con AnimEvent

Azione con durata indeterminata, completata tramite eventi animazione.
Esempio principale: `ISChopTreeAction` (tagliare un albero).

```lua
ISLoopedAction = ISBaseTimedAction:derive("ISLoopedAction")

function ISLoopedAction:isValid()
    return self.targetObject and self.targetObject:getObjectIndex() ~= -1
end

function ISLoopedAction:start()
    self:setActionAnim("Chop")
    self.sound = self.character:playSound("ChopSound")
end

function ISLoopedAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function ISLoopedAction:stop()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function ISLoopedAction:perform()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    if not isClient() then
        self:applyFinalHit()
    end
    ISBaseTimedAction.perform(self)
end

-- Durata -1 = infinita. Il completamento e' gestito da animEvent.
function ISLoopedAction:getDuration()
    return -1
end

-- SERVER: registra emulazione eventi animazione
function ISLoopedAction:serverStart()
    self.tool = self.character:getPrimaryHandItem()
    -- Emula l'evento "HitTarget" ogni 1500ms
    emulateAnimEvent(self.netAction, 1500, "HitTarget", nil)
end

-- SERVER: cleanup se cancellata
function ISLoopedAction:serverStop()
    -- Niente da pulire in questo esempio
end

-- Chiamato sia client che server quando l'evento animazione si attiva
function ISLoopedAction:animEvent(event, parameter)
    if event == "HitTarget" then
        if isServer() then
            -- Logica server-side: applica danno
            self.targetObject:WeaponHit(self.character, self.tool)
            if self.targetObject:getObjectIndex() == -1 then
                -- L'oggetto e' stato distrutto -> completa l'azione
                self.netAction:forceComplete()
            end
        end
        if isClient() then
            -- Effetti visivi client-side
            self.targetObject:WeaponHitEffects(self.character, self.tool)
        end
    end
end

function ISLoopedAction:complete()
    -- Chiamato quando forceComplete() viene invocato
    return true
end

function ISLoopedAction:new(character, targetObject)
    local o = ISBaseTimedAction.new(self, character)
    o.targetObject = targetObject
    o.maxTime = -1  -- Importante per il client
    o.stopOnWalk = true
    return o
end
```

---

## Pattern: Azione con aggiornamento progressivo

Per azioni che applicano effetti gradualmente (es. versare benzina, bere).

```lua
ISProgressiveAction = ISBaseTimedAction:derive("ISProgressiveAction")

function ISProgressiveAction:getDuration()
    return self.maxTime
end

-- SERVER: setup emulazione update periodico
function ISProgressiveAction:serverStart()
    -- Aggiorna ogni 1000ms (50 tick * 20)
    emulateAnimEvent(self.netAction, 1000, "update", nil)
end

-- SERVER: sincronizza stato parziale se interrotta
function ISProgressiveAction:serverStop()
    self.item:syncItemFields()
end

function ISProgressiveAction:animEvent(event, parameter)
    if isServer() then
        if event == "update" then
            -- Applica effetto progressivo basato sul progresso
            local progress = self.netAction:getProgress()  -- 0.0 - 1.0
            local amountToApply = self.totalAmount * progress - self.appliedAmount
            self:applyAmount(amountToApply)
            self.appliedAmount = self.appliedAmount + amountToApply
        end
    end
end

function ISProgressiveAction:complete()
    -- Applica il resto
    local remaining = self.totalAmount - self.appliedAmount
    if remaining > 0 then
        self:applyAmount(remaining)
    end
    self.item:syncItemFields()
    return true
end

function ISProgressiveAction:new(character, item, totalAmount)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.totalAmount = totalAmount
    o.appliedAmount = 0
    o.maxTime = 200
    return o
end
```

---

## Pattern: Azione senza timeout

Per azioni dove il server non dovrebbe forzare il completamento per timeout
(es. leggere un libro, dove il completamento dipende dal progresso).

```lua
ISNoTimeoutAction = ISBaseTimedAction:derive("ISNoTimeoutAction")

function ISNoTimeoutAction:isUsingTimeout()
    return false  -- Il server non forzera' il completamento
end

function ISNoTimeoutAction:getDuration()
    return -1  -- Durata infinita
end

function ISNoTimeoutAction:serverStart()
    local interval = self.maxTime * 8.0 / self.totalSteps
    emulateAnimEvent(self.netAction, interval, "Step", nil)
end

function ISNoTimeoutAction:animEvent(event, parameter)
    if event == "Step" then
        if isServer() then
            self.currentStep = self.currentStep + 1
            if self.currentStep >= self.totalSteps then
                self.netAction:forceComplete()
            end
        end
    end
end

function ISNoTimeoutAction:complete()
    -- Completamento finale
    return true
end

function ISNoTimeoutAction:new(character, item, totalSteps)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.totalSteps = totalSteps
    o.currentStep = 0
    o.maxTime = -1
    return o
end
```

---

## AnimEventEmulator

Il server non ha il motore di animazione. L'`AnimEventEmulator` simula gli eventi
con timer periodici.

### Funzioni globali Lua

```lua
-- Evento ripetuto ogni `duration` millisecondi
emulateAnimEvent(netAction, duration, eventName, parameter)

-- Evento singolo dopo `duration` millisecondi
emulateAnimEventOnce(netAction, duration, eventName, parameter)
```

### Parametri

| Parametro | Tipo | Descrizione |
|-----------|------|-------------|
| `netAction` | NetTimedAction | `self.netAction` (iniettato automaticamente server-side) |
| `duration` | long | Intervallo in millisecondi |
| `eventName` | String | Nome dell'evento (corrisponde al parametro `event` in `animEvent()`) |
| `parameter` | String/nil | Parametro extra passato a `animEvent()` |

### Timeout massimo

L'AnimEventEmulator ha un timeout massimo di **30 minuti** (1800000 ms).
Se un'azione looped dura piu' di 30 minuti senza completarsi, viene rimossa.

### Esempio pratico

```lua
function ISMyAction:serverStart()
    -- Ripeti "Hit" ogni 2 secondi
    emulateAnimEvent(self.netAction, 2000, "Hit", nil)

    -- Esegui "Setup" una volta dopo 500ms
    emulateAnimEventOnce(self.netAction, 500, "Setup", "param1")
end

function ISMyAction:animEvent(event, parameter)
    if event == "Setup" then
        -- Eseguito una volta sola, 500ms dopo l'inizio
    elseif event == "Hit" then
        -- Eseguito ogni 2 secondi
    end
end
```

---

## ISTimedActionQueue

La coda delle azioni e' gestita da `ISTimedActionQueue` (solo client-side).

### Aggiungere azioni

```lua
-- Singola azione
local action = ISMyAction:new(playerObj, item)
ISTimedActionQueue.add(action)

-- Piu' azioni in sequenza
ISTimedActionQueue.add(ISFirstAction:new(playerObj, item1))
ISTimedActionQueue.add(ISSecondAction:new(playerObj, item2))

-- Azione dopo una specifica
local action1 = ISFirstAction:new(playerObj, item1)
ISTimedActionQueue.add(action1)
ISTimedActionQueue.addAfter(action1, ISSecondAction:new(playerObj, item2))
```

### Aggiungere azioni durante perform()

Se un'azione deve aggiungere altre azioni quando completa:

```lua
function ISMyAction:perform()
    self:beginAddingActions()
    ISTimedActionQueue.add(ISFollowUpAction:new(self.character, self.result))
    self:endAddingActions()

    ISBaseTimedAction.perform(self)
end
```

Le azioni vengono inserite subito dopo quella corrente nella coda.

### Utilita della coda

```lua
-- Cancella tutta la coda di un personaggio
ISTimedActionQueue.clear(playerObj)

-- Verifica se un'azione e' in coda
ISTimedActionQueue.hasAction(action)

-- Verifica se un tipo di azione e' in coda
ISTimedActionQueue.hasActionType(playerObj, ISMyAction)

-- Verifica se il player sta facendo qualcosa
ISTimedActionQueue.isPlayerDoingAction(playerObj)

-- Ottieni la coda
local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
```

### Azioni che richiedono di alzarsi

```lua
-- L'azione viene eseguita solo dopo che il personaggio si e' alzato
ISTimedActionQueue.addGetUpAndThen(playerObj, ISMyAction:new(playerObj, item))
```

---

## adjustMaxTime

Il metodo `adjustMaxTime()` viene chiamato **solo client-side** durante `create()`.
Applica penalita automatiche alla durata basate sullo stato del personaggio:

| Condizione | Penalita |
|------------|----------|
| Infelicita (Unhappy moodle) | +25% per livello (0-4) |
| Ubriachezza (Drunk moodle) | +25% per livello (0-4) |
| Ferite alle mani/avambracci | +dolore/300 (cumulativo) |
| Temperatura corporea | moltiplicatore da `getTimedActionTimeModifier()` |

La penalita alle mani puo' essere disabilitata:
```lua
function ISMyAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.ignoreHandsWounds = true  -- Ignora penalita ferite mani
    o.maxTime = 100
    return o
end
```

Il server calcola la durata tramite `getDuration()` indipendentemente,
senza applicare `adjustMaxTime()`. Questo evita desincronizzazione.

---

## Campi e proprieta della tabella

### Campi impostabili nel costruttore `new()`

| Campo | Default | Descrizione |
|-------|---------|-------------|
| `maxTime` | `-1` | Durata in tick (-1 = infinita/looped) |
| `stopOnWalk` | `true` | Ferma l'azione se il giocatore cammina |
| `stopOnRun` | `true` | Ferma l'azione se il giocatore corre |
| `stopOnAim` | `true` | Ferma l'azione se il giocatore mira |
| `caloriesModifier` | `1` | Moltiplicatore calorie consumate |
| `useProgressBar` | `true` | Mostra la progress bar |
| `forceProgressBar` | `false` | Forza la progress bar anche se disabilitata nelle opzioni |
| `ignoreHandsWounds` | `false` | Ignora penalita ferite mani in adjustMaxTime |
| `loopedAction` | `false` | Se l'azione e' looped (non completa automaticamente) |

### Campi disponibili a runtime

| Campo | Disponibilita | Descrizione |
|-------|--------------|-------------|
| `self.character` | Sempre | Il personaggio che esegue l'azione |
| `self.action` | Dopo create() | L'oggetto Java `LuaTimedActionNew` |
| `self.netAction` | Solo server | Il `NetTimedAction` Java (per emulateAnimEvent, forceComplete) |
| `self.name` | Sempre | Nome univoco dell'istanza dell'azione |

### Animazioni specifiche sincronizzate in rete

Queste stringhe di animazione vengono sincronizzate automaticamente in rete:

```
"Reload", "Bandage", "Loot", "AttachItem", "Drink", "Eat",
"Pour", "Read", "fill_container_tap", "drink_tap", "WearClothing"
```

---

## Differenze Singleplayer vs Multiplayer

| Aspetto | Singleplayer | Multiplayer |
|---------|-------------|-------------|
| `complete()` | Chiamato localmente | Chiamato solo server |
| `perform()` | Contiene logica di gioco | Solo cleanup UI |
| `serverStart()` | NON chiamato | Chiamato sul server |
| `serverStop()` | NON chiamato | Chiamato sul server |
| `animEvent()` | Chiamato dal motore anim | Client: motore anim, Server: AnimEventEmulator |
| `adjustMaxTime()` | Applicato normalmente | Solo client, server usa getDuration() |
| `netAction` | Non disponibile (nil) | Disponibile solo server-side |
| `isClient()` | `false` | `true` sul client |
| `isServer()` | `false` | `true` sul server |
| `waitForFinished` | `false` | `true` (aspetta conferma server) |

### Pattern condizionale comune

```lua
function ISMyAction:perform()
    -- Cleanup (sempre)
    ISInventoryPage.dirtyUI()

    -- Logica di gioco: singleplayer in perform, multiplayer in complete
    if not isClient() then
        self:doWork()
    end

    ISBaseTimedAction.perform(self)
end

function ISMyAction:complete()
    -- Server-side (o singleplayer se non isClient)
    self:doWork()
    return true
end
```

In singleplayer:
- `isClient()` = `false`, `isServer()` = `false`
- `complete()` viene chiamato tramite `LuaTimedActionNew.complete()` solo se `!GameClient.client`
- `perform()` esegue la logica con il check `if not isClient()`

In multiplayer:
- Client: `isClient()` = `true`, `perform()` salta la logica
- Server: `isServer()` = `true`, `complete()` esegue la logica

---

## Errori comuni e troubleshooting

### 1. "L'azione non funziona in multiplayer"

**Causa**: La logica e' solo in `perform()` senza `complete()`.
**Fix**: Sposta la logica di gioco in `complete()` e ritorna `true`.

### 2. "Il server rifiuta sempre l'azione"

**Causa**: `complete()` ritorna `nil` invece di `true`.
**Fix**: Assicurati che `complete()` ritorni esplicitamente `true` o `false`.

### 3. "I parametri arrivano nil sul server"

**Causa**: I nomi dei parametri in `new()` non corrispondono ai campi della tabella.
**Fix**: I nomi dei parametri nel costruttore DEVONO essere identici ai nomi dei campi `self.xxx`.

```lua
-- SBAGLIATO
function ISMyAction:new(character, myItem)
    local o = ISBaseTimedAction.new(self, character)
    o.item = myItem  -- Il server cerchera' "myItem" nella tabella, trovera' nil!
    return o
end

-- CORRETTO
function ISMyAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item  -- "item" nel parametro == "item" nel campo
    return o
end
```

### 4. "Il Type non viene trovato sul server"

**Causa**: Il file e' in `lua/client/` oppure il Type non corrisponde alla variabile globale.
**Fix**: Metti il file in `lua/shared/` e assicurati che `derive("ISMyAction")` corrisponda a `ISMyAction = ...`.

### 5. "emulateAnimEvent non funziona"

**Causa**: Stai usando `self` al posto di `self.netAction`.
**Fix**: Usa `emulateAnimEvent(self.netAction, ...)` - il primo parametro deve essere il `NetTimedAction` Java.

### 6. "L'azione looped non si ferma mai"

**Causa**: Non stai chiamando `self.netAction:forceComplete()` in `animEvent()`.
**Fix**: Quando la condizione di completamento e' soddisfatta, chiama `self.netAction:forceComplete()` server-side.

### 7. "L'azione non rispetta le penalita del personaggio"

**Causa**: `adjustMaxTime()` gira solo client-side. Se `getDuration()` usa `self.maxTime`, il server avra' il valore originale.
**Fix**: Implementa la logica di penalita anche in `getDuration()` se serve che il server la consideri, oppure accetta che client e server avranno timer leggermente diversi (il server fa fede).

### 8. "L'azione va in timeout dopo 30 minuti"

**Causa**: L'`AnimEventEmulator` ha un timeout massimo di 30 minuti.
**Fix**: Per azioni molto lunghe, usa `isUsingTimeout()` che ritorna `false`.

### 9. "forceComplete() non funziona lato client"

**Causa**: In multiplayer, `forceComplete()` client-side completa solo l'animazione locale.
Il server deve confermare indipendentemente.
**Fix**: Server-side usa `self.netAction:forceComplete()`. Client-side usa `self:forceComplete()`.

---

## Riferimenti al codice sorgente

### File Lua

| File | Percorso |
|------|----------|
| ISBaseTimedAction | `media/lua/shared/TimedActions/ISBaseTimedAction.lua` |
| ISTimedActionQueue | `media/lua/client/TimedActions/ISTimedActionQueue.lua` |
| Azioni shared | `media/lua/shared/TimedActions/*.lua` |
| Azioni client | `media/lua/client/TimedActions/*.lua` |
| Azioni veicoli | `media/lua/shared/Vehicles/TimedActions/*.lua` |
| Azioni animali | `media/lua/shared/Animals/TimedActions/*.lua` |

### File Java (decompilati)

| Classe | Package |
|--------|---------|
| `LuaTimedActionNew` | `zombie.characters.CharacterTimedActions` |
| `LuaTimedAction` | `zombie.characters.CharacterTimedActions` (legacy) |
| `BaseAction` | `zombie.characters.CharacterTimedActions` |
| `NetTimedAction` | `zombie.core` |
| `ActionManager` | `zombie.core` |
| `Action` | `zombie.core` |
| `Transaction` | `zombie.core` |
| `NetTimedActionPacket` | `zombie.network.packets` |
| `AnimEventEmulator` | `zombie.network.server` |

### Azioni vanilla che usano emulateAnimEvent (35 file)

ISReadABook, ISRackFirearm, ISAddFluidFromItemAction, ISTakeFuel, ISDumpWaterAction,
ISUnloadBulletsFromMagazine, ISLoadBulletsInMagazine, ISInsertMagazine, ISReloadWeaponAction,
ISDrinkFluidAction, ISEjectMagazine, ISChopTreeAction, ISFitnessAction, ISRestAction,
ISAttachItemHotbar, ISBBQLightFromKindle, ISUnloadBulletsFromFirearm, ISRemoveBush,
ISMilkAnimal, ISPetAnimal, ISHutchCleanNest, ISShearAnimal, ISHutchCleanFloor,
ISLureAnimal, ISGatherBloodFromAnimal, ISHutchGrabEgg, ISGiveWaterToAnimal,
ISAddGasolineToVehicle, ISWashVehicle, ISTakeGasolineFromVehicle,
ISFluidEmptyAction, ISAddWaterToTrough, ISLightFromKindle, ISPickupFishAction,
ISTakeWaterAction
