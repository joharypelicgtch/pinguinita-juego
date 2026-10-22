# PIP: HOGAR DE CARTÓN (nombre tentativo)
**Survival 3D ligero de recolección y construcción · Godot 4 (GDScript) · PC de gama baja**

---

## 1. Resumen ejecutivo

**Concepto.** Una cría de pingüino (una niña chibi con traje/capucha de pingüino) queda huérfana tras la muerte de su madre, que salió a buscar comida y no volvió. Empieza sola en un bosque periférico, junta lo que encuentra, arma un refugio de cartón y, poco a poco, se abre camino hacia una ciudad pequeña, lluviosa y grande para ella.

**Pilares de diseño**
1. **Ternura frágil:** todo es enorme comparado con ella. La vulnerabilidad es el tono, no el castigo.
2. **Construir para sobrevivir:** el refugio es la meta, el hogar y la salud mental del jugador.
3. **Melancolía con esperanza:** música triste solo en momentos de tensión extrema; el resto del tiempo, sonidos pequeños y cálidos.
4. **Mundo distinto cada partida:** terreno, árboles y edificios se generan con una semilla.
5. **Cero gore:** la violencia máxima son patadas y empujones; nadie muere en pantalla.

**Estilo visual**
- Low-poly estilizado con cel-shading ligero (2 a 3 tonos) y contorno barato (casco invertido o shader de borde).
- Personaje chibi: cabeza grande, ojos grandes brillantes, **sin lágrimas**; la emoción va por postura, cejas y boca.
- Paleta bosque: verdes apagados y marrones cálidos. Paleta ciudad: grises azulados, charcos y luces cálidas de ventanas.
- Sin texturas pesadas: colores planos, vértices coloreados y una sola textura atlas de 512×512 para detalles.

**Datos técnicos objetivo**
- Motor: Godot 4.x, renderer **Compatibility** (OpenGL). Lenguaje: GDScript.
- Hardware mínimo: CPU antigua de 2 núcleos, **2 GB de RAM**, gráfica integrada, **Windows 10 LTSC**.
- Meta: 30 FPS estables a 1280×720 (escalable a 60 en equipos mejores). Uso de RAM del juego por debajo de 600 MB.
- Disco: sin problema. Aun así se recomienda mantener la build por debajo de 500 MB (menos carga, menos RAM).

---

## 2. Arquitectura de sistemas

### 2.1 Mapa de módulos

| Módulo | Tipo en Godot | Responsabilidad |
|---|---|---|
| `GameClock` | Autoload | Hora, día, ciclo día/noche, señales por hora/amanecer/anochecer |
| `WeatherManager` | Autoload | Clima por cadena de Markov, sesgo por bioma, tragedias (tormenta) |
| `AudioManager` | Autoload | Efectos, ambiente por clima/bioma, música solo en tensión extrema |
| `WorldGenerator` | Node3D | Terreno por semilla, árboles, ciudad, recursos y rutas de NPC |
| `Pinguinita` | CharacterBody3D | Movimiento, cámara, inventario, recibir golpes |
| `SurvivalStats` | Node (componente) | Salud, hambre, calor, estrés, desmayo |
| `HumanNPC` | CharacterBody3D | FSM de humanos: indiferente / benévolo / hostil |
| `BuildingSystem` | Node3D | Colocación libre con imanes, integridad, reparación, derrumbes |
| `PartnerSystem` | Node | Parejas candidatas, gustos, regalos, aceptación |
| `ChickManager` | Node | Crías, cuidado, pérdida o rescate por humano |
| `Main` | Node3D | Orquesta: luz solar, niebla, semilla, arranque |

Comunicación por **señales** (no polling): el clima emite `weather_changed`, el reloj emite `period_changed`, etc. Esto ahorra CPU.

### 2.2 Ciclo día/noche
- 1 día de juego = **8 minutos reales** (configurable).
- Un solo `DirectionalLight3D` rota con la hora; el color y la energía se interpolan con un `Gradient` (alba naranja, mediodía neutro, atardecer rosado, noche azul oscuro).
- De noche: más frío, más estrés, humanos hostiles más activos, la ciudad enciende luces (emisión de material, sin luces reales).
- **Sin luces dinámicas** salvo el sol; las lámparas son mallas emisivas.

### 2.3 Clima dinámico
- Estados: `CLEAR`, `CLOUDY`, `RAIN`, `STORM`.
- Transiciones por probabilidades (cadena de Markov). En la **ciudad** las probabilidades de `RAIN` y `STORM` se duplican para acentuar el tono melancólico.
- Efectos: niebla (ajustar `Environment.fog_density`), partículas de lluvia `GPUParticles3D` baja densidad (o `CPUParticles3D` si la gráfica es muy vieja), enfriamiento más rápido, charcos con material más oscuro.
- **Tragedias:** una tormenta puede disparar `tragedy("storm")`; el `BuildingSystem` daña piezas del refugio y las más débiles (cartón) pueden caerse. El jugador repara, no se pierde la partida.

### 2.4 IA de humanos (FSM)
Tres tipos, misma base, distintos pesos:

- **Indiferente (mayoría):** sigue su ruta; si la cría estorba, la **esquiva o la aparta con un empujón sin daño**.
- **Benévolo (ocasional):** si ve a la cría cerca, puede **dejar caer migas o comida** y seguir; sin interacción forzada.
- **Hostil (raro):** al detectarla, se acerca y **patea o empuja** (daño leve + impulso). Pierde interés si ella está dentro del refugio, lejos o tras un cooldown.

Estados: `WALK → (IGNORE | DROP_FOOD | CHASE → KICK → COOLDOWN) → WALK`.
Optimización: percepción a **5 Hz** (no cada frame), solo NPCs dentro del radio activo (máx. 12 humanos simultáneos), el resto pausado con `process_mode = DISABLED`.

### 2.5 Construcción: colocación libre con imanes
- El jugador elige una pieza, ve un **fantasma** (ghost) semitransparente y la mueve libremente sobre el terreno.
- Cada pieza define **sockets** (puntos de encaje). Si un socket del fantasma queda a menos de 0.6 m de un socket existente, se **imanta** y alinea posición y rotación.
- Rotación con Q/E, confirmar con clic izquierdo, cancelar con clic derecho.
- Piezas por tiers:
  1. **Cartón** (caja, panel, techo de cartón): barato, débil, se moja.
  2. **Madera/ramas** (pared, techo inclinado): más resistente.
  3. **Mixto/reforzado** (tela, plástico, tapas): aislante, sobrevive a tormentas.
- Cada pieza tiene **integridad (HP)**; la lluvia desgasta el cartón, las tormentas dañan todo. Reparar cuesta materiales.
- **Refugio = Area3D** generada por las piezas que dan cobijo; mientras la cría esté dentro, `sheltered = true` (menos frío, menos estrés, recupera salud).

### 2.6 Generación aleatoria con límite
- Todo parte de una **semilla** (`seed`). Misma semilla = mismo mapa; nueva partida = mapa nuevo.
- **Bosque:** terreno con `FastNoiseLite` (colinas suaves), claro de inicio plano, árboles por rejilla con jitter (nunca en el mismo lugar), recursos naturales dispersos.
- **Ciudad:** cuadrícula de manzanas; en cada una se sortea edificio (tamaño y altura aleatorios), parque o solar. Calles fijas, edificios cambian de sitio. Genera además **waypoints** de aceras para los humanos.
- **Límite:** mapa acotado (bosque ≈ 160×160 m, ciudad ≈ 160×160 m) con una **zona de transición** (carretera/sendero). Se generan **por zonas** y se descarga la que no se usa.

### 2.7 Audio
- Muchos **efectos pequeños**: pasos (según suelo), crujido de cartón, hojas, gotas, patada/golpe suave, campanita al recibir regalo, etc.
- **Ambiente** por capas: viento/pájaros (bosque), tráfico lejano (ciudad), lluvia (volumen según intensidad).
- **Música melancólica solo en tensión extrema** (salud baja, estrés alto, crías en peligro). Entra con *fade* cuando `tension > 0.75` y sale cuando baja de `0.55` (histéresis para evitar parpadeo).

---

## 3. Mecánicas detalladas: de huérfana a protectora

### Fase 1: Huérfana (bosque)
- **Objetivo:** sobrevivir los primeros días y armar el primer refugio.
- Recolecta: **ramitas, hojas**, algo de cartón suelto y comida (bayas, migas).
- Estadísticas: salud, hambre, calor, estrés.
- Primer craft: **Caja de cartón** (cartón + hojas). Da cobijo básico y es el punto de reaparición.
- Escena inicial breve y emotiva (cámara cerca de la caja, el peluche/bufanda de la madre como objeto simbólico). Sin diálogo.
- Tragedia suave: la primera tormenta puede derrumbar la caja si no se refuerza.

### Fase 2: Refugio (bosque → ciudad)
- Desbloqueo de mejoras: paneles de madera, techo inclinado, tela aislante, tapas de plástico como "tejas".
- Explorar la ciudad para conseguir materiales mejores: **cartones grandes, tapas, restos de tela, basuritas**.
- Comienza el encuentro con humanos: la mayoría indiferente, algunos dejan migas, algunos hostiles.
- Puede construir un **refugio avanzado** (varias piezas) en la ciudad o regresar al del bosque; ambos persisten.
- Si el estrés se acumula o la salud llega a 0: **desmayo**, no muerte. Despierta en el refugio más cercano con penalización leve (pierde parte del inventario y avanza el tiempo).

### Fase 3: Pareja
- Aparecen **varios NPC candidatos** (pingüinos con traje de distintos colores/accesorios) en zonas específicas.
- Cada uno tiene **gustos y desagrados** (ramita especial, flor, tapa brillante, tela suave…).
- El jugador ofrece un **regalo**. El NPC **decide**: acepta (sube confianza) o rechaza (se aleja un tiempo).
- Si acepta 2 regalos y el refugio tiene al menos tier 2, **se muda con la cría**.
- Una pareja distinta tiene distinta personalidad (más valiente, más tímida), lo que afecta su ayuda: vigila de noche, recolecta, o consuela.

### Fase 4: Protección de crías
- Pasados unos días de convivencia estable, **nace una cría** (hasta 2 o 3 en total).
- **Sin herencia:** las crías no se juegan ni transmiten rasgos; son responsabilidad, no personajes controlables.
- Cada cría tiene **cuidado** (comida, calor, compañía). Se cuida llevándola al refugio, dándole comida y manteniéndola seca.
- Si se **descuida** (cuidado bajo demasiado tiempo, a la intemperie en tormenta o cerca de humanos hostiles), ocurre un evento **sin gore**:
  - **Se la lleva un humano:** aparece una escena corta y suave (alguien la recoge con cariño). Es una pérdida permanente.
  - **Se pierde:** se aleja y desaparece; hay una **ventana corta** para encontrarla con pistas de sonido y huellas.
- **Final de partida:** sandbox con "capítulos" opcionales. Un final suave aparece tras cuidar a las crías X días (o al perder la última).

### Progresión y economía
- Recursos clave: `twig`, `leaf`, `cardboard`, `bottle_cap`, `cloth_scrap`, `trash`, `crumbs`, `special_twig`.
- Sin dinero. El progreso es **calidad del refugio** y **relaciones**.
- Dificultad: la ciudad escala con la noche y la lluvia, no con enemigos más fuertes.

---

## 4. Guía de optimización para PC de gama baja

**Render y proyecto**
- Renderer **Compatibility** (OpenGL 3.3). Si la integrada es muy vieja (solo OpenGL 2.1), no hay soporte en Godot 4: hay que verificarlo en la PC objetivo antes de comprometer el motor.
- Resolución de renderizado a 1280×720 con **escala 3D** ajustable (0.7 a 1.0) y opciones: Bajo / Medio.
- **Sin**: SDFGI, GI, SSAO, SSR, glow, volumetric fog, reflection probes.
- **Sombras:** una sola luz con sombra, distancia corta (40 a 60 m), mapa de sombras 1024, o **blob shadows** (decal/sprite redondo bajo personajes). Opción "sin sombras".
- **MSAA/FXAA:** apagados por defecto.

**Geometría**
- Presupuesto: personaje 1500 a 2500 tris; humano 1500; árbol 150 a 300; edificio 50 a 300.
- Todo lo repetido en **MultiMeshInstance3D** (árboles, ramitas, hojas, edificios, farolas).
- **LOD automático** de Godot (importar mallas con LOD) y `visibility_range_end` para pequeños detalles.
- Máximo de **~600 draw calls** y **~150 k triángulos** visibles.

**Materiales y texturas**
- Colores planos y vertex color; **un atlas de 512×512** (o 1024) con compresión **VRAM/ETC2/S3TC**.
- Shader cel con **2 a 3 tonos** (sin cálculos de iluminación complejos, un solo `light()` simple).
- Contorno con malla invertida (barato) solo en personajes principales.

**CPU y memoria**
- **Pools de objetos** (migas, ramitas, partículas, sonidos).
- IA a **5 Hz**, física solo para lo cercano; NPCs lejanos desactivados.
- Navegación: **waypoints** (rutas simples) en vez de NavMesh pesado para humanos de ciudad.
- Generación **por zonas, en hilo (`WorkerThreadPool`)** y con carga progresiva; descargar zonas lejanas.
- Evitar `get_node()`/`find_children` en `_process`; cachear con `@onready`.
- Partículas: máx. 300 de lluvia en baja calidad (`CPUParticles3D` si no hay GPU decente).
- **Audio:** OGG mono a 22 kHz para efectos; música en OGG streaming; máx. ~16 voces.

**Presupuestos de memoria (2 GB totales, Win10 LTSC ≈ 0.8 a 1 GB en uso)**
| Recurso | Presupuesto |
|---|---|
| Texturas | ≤ 150 MB |
| Mallas | ≤ 80 MB |
| Audio en RAM | ≤ 60 MB |
| Scripts/escena/nodos | ≤ 150 MB |
| **Total del juego** | **≤ 600 MB** |

**Exportación**
- Plantilla de exportación en **release** (no debug), Windows 64 bits, y activar "strip" de símbolos.
- Probar en la PC objetivo con el **Monitor** de Godot (FPS, memoria, draw calls) antes de añadir contenido.

---

## 5. Estructura base de scripts (ver archivos .gd adjuntos)

```
res://
├─ autoload/
│  ├─ game_clock.gd        (GameClock)
│  ├─ weather_manager.gd   (WeatherManager)
│  └─ audio_manager.gd     (AudioManager)
├─ player/
│  ├─ player.gd            (Pinguinita)
│  └─ survival_stats.gd    (SurvivalStats)
├─ npc/
│  └─ human_npc.gd         (HumanNPC)
├─ world/
│  ├─ world_generator.gd   (WorldGenerator)
│  └─ main.gd              (Main)
└─ systems/
   ├─ building_system.gd   (BuildingSystem)
   ├─ partner_system.gd    (PartnerSystem)
   └─ chick_manager.gd     (ChickManager)
```

**Autoloads a registrar** (Proyecto > Configuración > Globales > Autoload): `GameClock`, `WeatherManager`, `AudioManager`.

**Acciones de entrada** (el jugador las crea solo en código si no existen): `move_forward/back/left/right` (WASD), `run` (Shift), `jump` (Espacio), `interact` (E), `build_toggle` (B), `build_rotate_left/right` (Q/E en modo construcción), `place` (clic izq.), `cancel` (clic der.).

---

## 6. Supuestos y siguientes pasos
- Un solo slot de guardado local (JSON con semilla + estado de refugio, parejas, crías y estadísticas).
- Idioma solo español.
- Ejecutable para Windows 64 bits (Godot 4.x oficial).
- **Riesgo a validar primero:** que la gráfica integrada soporte OpenGL 3.3. Si no, el plan B es Godot 3.x (OpenGL ES 2) o una versión web 3D.
- **Siguiente hito sugerido (vertical slice):** bosque + caja de cartón + ciclo día/noche + lluvia + 1 humano hostil + recolección y construcción básica.
