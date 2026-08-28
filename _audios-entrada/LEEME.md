# Buzón de audios para transcribir

Carpeta temporal. Sube aquí los audios en inglés que quieras transcribir.

## Cómo subir

1. Entra a esta carpeta en GitHub, en **esta rama** (`buzon-audios`).
2. Botón **Add file → Upload files**.
3. Arrastra los mp3 y dale **Commit changes**.

Límite de GitHub por el navegador: **25 MB por archivo**.

## Reglas de esta carpeta

- **Esta rama NO se mergea a `main` nunca.** Si se mergeara, los audios
  quedarían publicados en `montaguth.institute/_audios-entrada/` y grabados
  en el historial del sitio para siempre.
- Es un buzón de paso: cuando la transcripción esté entregada, la rama se
  borra y los audios dejan de ser alcanzables.
- Formatos que puedo procesar: mp3, wav, m4a, ogg, opus, flac, mp4, webm.

## Qué recibes de vuelta

- El texto corrido, en el chat.
- Un `.srt` con marcas de tiempo, si lo pides.

Modelo usado: Whisper `small.en` (el más preciso de los tres), corriendo en
el entorno de Kiro. Tu audio no pasa por ninguna API de pago ni servicio de
terceros.
