# Emergencias: Sistema distribuido de coordinación y gestión de emergencias

Proyecto final de **Programación III** · Universidad del Quindío · Ingeniería de Sistemas y Computación.

Sistema multiusuario escrito en **Elixir** que simula una plataforma para coordinar la atención posterior a un terremoto: usuarios, zonas, necesidades, recursos, personas afectadas y mensajes entre familiares, mascotas perdidas o encontradas y albergues. Los componentes trabajan de forma concurrente (procesos, `GenServer` y supervisores) y evitan inconsistencias cuando varias operaciones ocurren al mismo tiempo.

## Integrantes

| Nombre completo | Código | Correo |
|---|---|---|
| Juan Miguel Gutierrez Vargas | 1091885531 | juanm.gutierrezv@uqvirtual.edu.co |
| Natalia Contreras Mora | 1013120297 | natalia.contrerasm@uqvirtual.edu.co |

## Requisitos

- Elixir 1.14 o superior y Erlang/OTP compatible. Verificar con `elixir --version`.
- Git.

## Cómo ejecutar

```bash
git clone https://github.com/Miguelx2201/p3-proyecto-final
cd emergencias
mix deps.get          # descarga dependencias
mix compile           # compila el proyecto
mix emergencias       # consola interactiva con la aplicación iniciada
mix test              # ejecuta las pruebas
mix run -e "Emergencias.Demo.flujo_ejemplo()" # ejecuta el flujo de ejemplo propuesto 
mix run -e "Emergencias.Demo.conflicto_concurrente()" # ejecuta el conflicto concurrente 
```

## Estructura del proyecto

```
lib/emergencias.ex                 fachada: API única del sistema
lib/emergencias/application.ex     árbol de supervisión
lib/emergencias/util.ex            entrada/salida y conversión segura de texto
lib/emergencias/csv.ex             lectura y escritura de CSV
lib/emergencias/persistencia.ex    guardar y cargar cada entidad
lib/emergencias/dominio/           entidades (structs y funciones puras)
lib/emergencias/servicios/         lógica que combina varias entidades (funciones puras)
lib/emergencias/procesos/          procesos: GenServer, DynamicSupervisor y proceso plano
lib/emergencias/cli/               consola: parser, comandos, bucle y formato
test/                              pruebas (un archivo por módulo)
test/support/                      ayudas para pruebas
data/                              archivos CSV generados (no se suben a git)
docs/diagramas/                    diagramas finales
```

## Convenciones del equipo

**Resultados.** Toda función de dominio devuelve `{:ok, valor}` o `{:error, razon}`, con `razon` como átomo (`:no_encontrado`, `:id_duplicado`, `:cantidad_invalida`, `:sin_stock`, `:sin_cupo`, `:transicion_invalida`, `:ya_cerrada`, `:permiso_denegado`, `:credenciales_invalidas`...). Está prohibido usar `raise`, `throw`, funciones con `!` y `String.to_integer` o `String.to_atom` sobre texto del usuario. Se usan `with`, `case` y pattern matching.

**Entidades inmutables.** Cada entidad es un `defstruct`. Sus funciones reciben la struct y devuelven una nueva. La lógica de negocio vive en módulos puros; los `GenServer` solo guardan el estado y llaman a esos módulos.

**Entidad vs servicio.** Si una función usa una sola entidad, va en el módulo de la entidad. Si usa varias entidades o una colección completa (asignar, reportes, ordenar), va en un módulo de `servicios`.

**Identificadores.** Strings: necesidades `N001`, recursos `R001`, albergues `A01`, mascotas `M001`, mensajes `MS001`, zonas por código (`centro`), personas por documento.

**Nombres.** Código en español, sin tildes ni `ñ` en los identificadores. Módulos bajo `Emergencias.Dominio`, `Emergencias.Servicios`, `Emergencias.Procesos` y `Emergencias.CLI`.

**Enumeraciones (átomos).**

| Concepto | Valores |
|---|---|
| Tipo de usuario | `:ciudadano`, `:voluntario`, `:coordinador`, `:administrador` |
| Nivel de afectación | `:critico`, `:alto`, `:medio`, `:bajo` |
| Prioridad de necesidad | `:critica`, `:alta`, `:media`, `:baja` (pesos 4, 3, 2, 1) |
| Tipo de necesidad / categoría de recurso | `:agua`, `:alimentos`, `:medicamentos`, `:primeros_auxilios`, `:refugio`, `:transporte`, `:rescate`, `:otra` |
| Estado de necesidad | `:pendiente`, `:asignada`, `:en_atencion`, `:atendida`, `:cancelada` |
| Estado de persona | `:sin_informacion`, `:reportada`, `:localizada`, `:trasladada`, `:en_albergue`, `:reunificada` |
| Estado de mensaje | `:pendiente`, `:entregado` |
| Mascota: tipo / estado / tamaño | `:perdida`, `:encontrada` / `:activa`, `:posible_coincidencia`, `:resuelta` / `:pequeno`, `:mediano`, `:grande` |

**Persistencia.** CSV con separador `;`, una cabecera por archivo, carpeta `data/`. Los textos libres se sanitizan (se reemplazan `;` y saltos de línea por espacio). Las estructuras anidadas se guardan en archivos aparte, una fila por elemento. Cada `GenServer` carga su archivo en `init/1` y lo reescribe después de cada cambio exitoso.

**Fechas.** `DateTime.utc_now() |> DateTime.to_iso8601()`.

### Patrón GenServer

Cada llamada entra por `handle_call`, que procesa un mensaje a la vez. Eso serializa las operaciones y evita las condiciones de carrera.

### Árbol de supervisión propuesto

```
Emergencias.Supervisor (one_for_one)
 ├─ Registry (Emergencias.Registry)
 ├─ RegistroActividad        proceso plano (spawn_link + receive recursivo)
 ├─ UsuariosServer, ZonasServer, NecesidadesServer,
 │  RecursosServer, PersonasServer, MascotasServer     (GenServer)
 └─ AlberguesSupervisor      (DynamicSupervisor)
      └─ AlbergueServer A01, A02...   (un GenServer por albergue)
```
