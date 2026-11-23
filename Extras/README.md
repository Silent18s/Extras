# SnowX Extras

`AvatarBridge.lua` es únicamente el contrato de integración y registro de APIs. No descarga, combina ni ejecuta Skins o Accessories.

Los módulos independientes viven en la raíz del repositorio: `SnowX-Skins.lua` y `SnowX-Accessories.lua`. Cada uno se ejecuta por separado y comparte `__SnowXAvatarBridge` cuando ambos se encuentran en el mismo entorno.
