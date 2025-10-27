# 🏦 KipuBank V2

**KipuBankV2** es una versión mejorada del contrato `KipuBank` original.  
Permite realizar **depósitos y retiros de ETH y tokens ERC-20**, consultando precios en **oráculos Chainlink** para expresar su valor en USD.  
Incluye **medidas avanzadas de seguridad**, **modificadores reutilizables** y un **sistema de control de pausas** para garantizar operaciones confiables.

---

## 🚀 Mejoras principales respecto a KipuBank V1

### 🔹 1. Estructura modular y legible
- El código está completamente reorganizado en secciones: *Variables, Eventos, Errores, Modificadores, Funciones, etc.*  
- Se mejoró la **claridad y mantenibilidad** del código sin alterar su lógica original.

### 🔹 2. Modificadores para validaciones comunes
- Validaciones reutilizables (`validAmount`, `nonReentrant`, `validToken`, `whenNotPaused`, `withinWithdrawLimit`) que simplifican el código y mejoran la seguridad.

### 🔹 3. Integración con Chainlink
- Uso de **oráculos ETH/USD** y **oráculos configurables por token**.
- Funciones `getLatestETHPrice()` y `getLatestTokenPrice()` permiten obtener precios actualizados directamente desde la blockchain.

### 🔹 4. Seguridad reforzada
- Protección contra **reentrancia**.
- **Modo pausa** para emergencias.
- **Límites configurables**:
  - Capacidad total del banco (`i_bankCap`) expresada en USD.
  - Límite máximo de retiro individual (`i_withdrawLimit`).

---

## ⚙️ Instrucciones de despliegue (Remix IDE)

### 🧱 Requisitos previos

- [Remix IDE](https://remix.ethereum.org)
- Una cuenta en **MetaMask** conectada a una red de prueba (por ejemplo, **Sepolia**).
- Dirección del **oráculo ETH/USD de Chainlink** según la red (por ejemplo, en Sepolia:  
  `0x694AA1769357215DE4FAC081bf1f309aDC325306`).

---

### 🧩 Pasos para desplegar el contrato

1. Abre [Remix](https://remix.ethereum.org).  
2. Crea un nuevo archivo llamado `KipuBankV2.sol` y pega el contenido completo del contrato.
3. Compila el contrato seleccionando:
   - **Compilador:** `0.8.20`
   - **EVM version:** `default`
   - Activa la opción **Auto compile** (opcional).
4. En el panel izquierdo, ve a la pestaña **Deploy & Run Transactions**.
5. Selecciona el **ambiente de ejecución**:
   - `Injected Provider - MetaMask` (para usar tu cuenta real o de prueba).
6. Completa los parámetros del constructor:
   - `_bankCap`: capacidad total en USD (por ejemplo, `1000000000000000000000000` para 1 millón USD con 18 decimales).
   - `_withdrawLimit`: límite máximo de retiro (por ejemplo, `10000000000000000000` para 10 ETH).
   - `_oracle`: dirección del oráculo ETH/USD de Chainlink.
7. Haz clic en **Deploy** y confirma la transacción en MetaMask.
8. Una vez desplegado, el contrato aparecerá en la sección **Deployed Contracts**.

---

## 💻 Interacción desde Remix

### 📥 Depositar ETH
- En la sección **Deployed Contracts**, abre el desplegable del contrato.
- En el campo **Value**, ingresa la cantidad de ETH que deseas depositar (por ejemplo, `1`).
- Haz clic en `depositETH`.

### 📥 Depositar tokens ERC-20
1. Desde el contrato del token, ejecuta `approve()` indicando:
   - El `spender`: dirección del contrato KipuBankV2.
   - El `amount`: cantidad de tokens a autorizar.
2. Luego, en KipuBankV2, ejecuta:
   - `depositToken(tokenAddress, amount)`.

### 💸 Retirar ETH o tokens
- Ejecuta `withdrawETH(amount)` o `withdrawToken(tokenAddress, amount)` según el tipo de activo.
- El monto debe respetar el límite `i_withdrawLimit`.

### 📊 Consultas útiles
- `balanceOf(token, user)`: muestra el balance del usuario en ese token.
- `getLatestETHPrice()`: obtiene el precio actual del ETH en USD.
- `totalBankValueUSD()`: devuelve el valor total acumulado en el banco.

### 🛠️ Funciones administrativas (solo owner)
- `pause()`: pausa todas las operaciones.
- `unpause()`: reanuda operaciones.
- `setOracle(newOracle)`: actualiza el oráculo de ETH/USD.
- `setTokenOracle(token, oracleAddress)`: asigna un oráculo específico para un token ERC-20.
- `emergencyWithdraw(token, amount)`: permite al owner retirar fondos solo en caso de emergencia.

---

## 🧩 Decisiones de diseño y trade-offs

### 🧱 Inmutabilidad de límites
Los valores `i_bankCap` e `i_withdrawLimit` se definen como **inmutables**, asegurando que no puedan modificarse luego del despliegue.  
➡️ *Ventaja:* mayor seguridad.  
➡️ *Trade-off:* menor flexibilidad.

### 🔒 Seguridad manual contra reentrancia
Se implementó un sistema manual de bloqueo (`locked`) en lugar de usar `ReentrancyGuard` de OpenZeppelin.  
➡️ *Ventaja:* ahorro de gas y control total del flujo.  
➡️ *Trade-off:* mayor responsabilidad en el manejo del flag.

### 📉 Valor total en USD
El campo `s_totalUSDValue` se actualiza solo en depósitos y retiros, sin recalcular con cada cambio de precio del oráculo.  
➡️ *Ventaja:* eficiencia en gas.  
➡️ *Trade-off:* precisión contable ligeramente menor.

### ⚙️ Sistema flexible de oráculos
Se permite asignar oráculos específicos por token, mejorando la compatibilidad con activos variados.  
➡️ *Ventaja:* flexibilidad.  
➡️ *Trade-off:* el owner debe configurar correctamente los oráculos.

---

## 🧾 Licencia

 © 2025 — Desarrollado por **Fernando Rojas**.

---
