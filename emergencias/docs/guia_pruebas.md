# Guía de pruebas (ExUnit)

## Cómo ejecutarlas

```bash
mix test                                # todas
mix test test/csv_test.exs              # un archivo
mix test test/csv_test.exs:25           # la prueba que está en esa línea
mix test --cover                        # con cobertura
mix test --failed                       # solo las que fallaron la última vez
```

## Lo básico

- Los archivos viven en `test/` y terminan en `_test.exs`. Uno por módulo: `lib/emergencias/util.ex` → `test/util_test.exs`.
- `use ExUnit.Case, async: true` corre el archivo en paralelo con los demás. Usar `async: false` si la prueba usa procesos con nombre global (los `GenServer`) o cambia configuración global (`Application.put_env`).
- `assert` comprueba que algo es verdadero y `refute` que es falso. Con pattern matching comprueba la forma del resultado:

```elixir
assert {:ok, %Recurso{cantidad_disponible: 20}} = Recurso.salida(recurso, 30)
assert {:error, :sin_stock} = Recurso.salida(recurso, 51)
```

- `describe "nombre"` agrupa pruebas y `setup` prepara datos antes de cada una.
- `assert_raise` se usa solo para probar que **no** se crean átomos o para errores de la propia prueba; las funciones de dominio no lanzan excepciones, devuelven `{:error, razon}`.

## Datos de prueba: Fabrica

`test/support/fabrica.ex` construye entidades válidas. Se sobrescribe lo que importe para la prueba:

```elixir
alias Emergencias.Fabrica

recurso = Fabrica.recurso(cantidad_disponible: 50)
necesidad = Fabrica.necesidad(prioridad: :baja, cantidad_requerida: 5)
```

Si una entidad cambia sus campos, se actualiza su función en `Fabrica` en el mismo Pull Request.

## Archivos y carpetas temporales

- Las pruebas usan la carpeta `tmp/test_data` (configurada en `config/test.exs`), nunca `data/`. Se vacía al iniciar `mix test`.
- Para una carpeta propia de una prueba: `@tag :tmp_dir` (o `@moduletag :tmp_dir`) y recibirla en el contexto: `test "...", %{tmp_dir: dir} do`.

## Antes de pedir revisión

1. `mix format`
2. `mix compile --warnings-as-errors`
3. `mix test`
4. El Pull Request incluye el archivo de prueba del módulo nuevo: caso válido, un caso inválido por cada validación y cada transición de estado válida e inválida.
