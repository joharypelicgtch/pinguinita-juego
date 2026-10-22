# Pip: Hogar de Cartón

Survival 3D ligero de recolección y construcción, hecho en **Godot 4 (GDScript)** y pensado para PCs de gama baja (2 GB de RAM, gráfica integrada, Windows 10 LTSC).

Una cría huérfana con traje de pingüino sobrevive en un bosque, arma un refugio de cartón, llega a una ciudad lluviosa, encuentra pareja y protege a sus crías. Sin gore: la violencia máxima son patadas y empujones.

> Estado: **prototipo jugable mínimo**. Abre una escena generada por código (bosque aleatorio, jugador, recursos, HUD); faltan modelos, audio y escenas propias.

## Características de diseño
- Mapa aleatorio con semilla (bosque + ciudad), con límites.
- Ciclo día/noche y clima dinámico (más lluvia en la ciudad, tormentas que dañan el refugio).
- Construcción libre con imanes (sockets), integridad y reparación.
- Humanos: indiferentes, benévolos (migas) y hostiles (patadas/empujones).
- Pareja por regalos; crías que se pierden o se las lleva un humano si no se cuidan.
- Música melancólica solo en tensión extrema.

## Estructura
```
autoload/   GameClock, WeatherManager, AudioManager (registrados en project.godot)
player/     Pinguinita (controlador + cámara), SurvivalStats
npc/        HumanNPC (FSM a 5 Hz) + human.tscn
world/      WorldGenerator, Main (orquestador)
systems/    BuildingSystem, PartnerSystem, ChickManager
audio/      sfx/, ambient/, music/  (poner aquí los .ogg)
docs/       GDD.md (documento de diseño completo)
```

## Cómo abrirlo
1. Instala [Godot 4.3+](https://godotengine.org/download) (versión estándar, GDScript).
2. Importa la carpeta (`project.godot`). Ya usa el renderer **Compatibility** y tiene los 3 Autoloads.
3. Pulsa **F5**: la escena principal (`world/main.tscn`) construye todo por código (`world/bootstrap.gd`). Cuando tengas escenas propias, reemplázala siguiendo el comentario de `world/main.gd`.
4. Añade audios `.ogg` con los nombres de `autoload/audio_manager.gd` (si faltan, simplemente no suenan).

## Controles
WASD mover · Shift correr · Espacio saltar · Ratón cámara · B construir · Q/E girar pieza · Clic izq. colocar · Clic der. cancelar · E interactuar/reparar · Esc liberar ratón.

## Compilación automática (GitHub Actions)
`.github/workflows/build.yml` exporta **Windows (.exe)** y **Linux** con Godot 4.3 en cada push/PR a `main`.
- Los ejecutables quedan en la pestaña **Actions → ejecución → Artifacts**.
- Para publicar una descarga pública: `git tag v0.1.0 && git push --tags` (se crea un *Release* con los ZIP).
- Los presets de exportación están en `export_presets.cfg` (versionado a propósito).

## Pendiente (vertical slice)
Bosque + caja de cartón + ciclo día/noche + lluvia + 1 humano hostil + recolección y construcción básica. Primero validar que la gráfica objetivo soporte OpenGL 3.3.

## Licencia
MIT (ver `LICENSE`).
