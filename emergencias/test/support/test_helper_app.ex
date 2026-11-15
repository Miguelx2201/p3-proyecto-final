defmodule Emergencias.TestHelperApp do
  @moduledoc """
  Ayudas para las pruebas de procesos y de concurrencia. Solo se compila con
  `MIX_ENV=test`.

  `mix test` no arranca la aplicación (`--no-start`). Estas pruebas necesitan el
  árbol de supervisión completo, así que cada una lo arranca con `reiniciar/1`
  y lo detiene al terminar con `detener_y_limpiar/0`.

  Los servidores tienen nombre global: las pruebas que usan este módulo deben
  ser `async: false`.

  Este módulo no usa `ExUnit.Assertions`: las funciones devuelven valores y las
  pruebas son las que afirman.
  """

  @contrasena "1234"
  @zona "centro"
  @timeout_tarea 30_000
  @intervalo_espera 10

  # ---------------------------------------------------------------------------
  # Arranque y limpieza de la aplicación
  # ---------------------------------------------------------------------------

  @doc """
  Detiene la aplicación, prepara la carpeta de datos y la vuelve a arrancar.

  Opciones:

    * `:borrar_datos` (por defecto `true`): borra la carpeta de datos con
      `File.rm_rf/1` antes de arrancar. Con `false` se conservan los CSV, para
      probar que los datos sobreviven a un reinicio.

  Devuelve `:ok` o `{:error, razon}`. Por seguridad solo toca la carpeta de
  datos si está dentro de `tmp/` (igual que `test_helper.exs`).
  """
  @spec reiniciar(keyword()) :: :ok | {:error, term()}
  def reiniciar(opciones \\ []) do
    borrar? = Keyword.get(opciones, :borrar_datos, true)

    with {:ok, carpeta} <- carpeta_de_datos(),
         :ok <- detener_aplicacion(),
         :ok <- preparar_carpeta(carpeta, borrar?),
         {:ok, _aplicaciones} <- Application.ensure_all_started(:emergencias) do
      :ok
    end
  end

  @doc """
  Detiene la aplicación y deja vacía la carpeta de datos. Se usa en `on_exit`
  para no dejar procesos con nombre ni archivos a las pruebas que siguen.
  """
  @spec detener_y_limpiar() :: :ok | {:error, term()}
  def detener_y_limpiar do
    with {:ok, carpeta} <- carpeta_de_datos(),
         :ok <- detener_aplicacion() do
      preparar_carpeta(carpeta, true)
    end
  end

  # Con `--no-start` la primera vez la aplicación no está arrancada: no es un error.
  defp detener_aplicacion do
    case Application.stop(:emergencias) do
      :ok -> :ok
      {:error, {:not_started, :emergencias}} -> :ok
      {:error, _razon} = error -> error
    end
  end

  defp carpeta_de_datos do
    case Application.get_env(:emergencias, :data_dir) do
      "tmp/" <> _resto = carpeta -> {:ok, carpeta}
      _otra -> {:error, :carpeta_de_datos_insegura}
    end
  end

  defp preparar_carpeta(carpeta, true) do
    case File.rm_rf(carpeta) do
      {:ok, _archivos} -> File.mkdir_p(carpeta)
      {:error, razon, _archivo} -> {:error, razon}
    end
  end

  defp preparar_carpeta(carpeta, false), do: File.mkdir_p(carpeta)

  # ---------------------------------------------------------------------------
  # Escenario base
  # ---------------------------------------------------------------------------

  @doc "Contraseña del usuario que crea `preparar_escenario/0`."
  @spec contrasena() :: String.t()
  def contrasena, do: @contrasena

  @doc """
  Conecta (y registra) al coordinador `laura` y crea la zona `centro`.
  Devuelve `{:ok, usuario}`. Un coordinador tiene permiso para todos los
  comandos que usan las pruebas.
  """
  @spec preparar_escenario() :: {:ok, struct()} | {:error, term()}
  def preparar_escenario do
    with {:ok, usuario} <- Emergencias.connect("laura", @contrasena, :coordinador, @zona),
         {:ok, _zona} <- Emergencias.register_zone(usuario, @zona, "Zona Centro", :critico) do
      {:ok, usuario}
    end
  end

  @doc "Registra un recurso de agua (litros) en la zona `centro`."
  @spec registrar_agua(struct(), String.t(), integer()) :: {:ok, struct()} | {:error, term()}
  def registrar_agua(usuario, id, cantidad) do
    Emergencias.register_resource(
      usuario,
      id,
      :agua,
      cantidad,
      "litros",
      "centro_acopio_1",
      @zona
    )
  end

  @doc "Registra una necesidad crítica de agua en la zona `centro`."
  @spec registrar_necesidad_agua(struct(), integer()) :: {:ok, struct()} | {:error, term()}
  def registrar_necesidad_agua(usuario, cantidad) do
    Emergencias.register_need(
      usuario,
      :agua,
      cantidad,
      :critica,
      @zona,
      "Punto de atención sector 3"
    )
  end

  @doc "Documento de prueba número `n`: `D001`, `D002`..."
  @spec documento(pos_integer()) :: String.t()
  def documento(n), do: "D" <> String.pad_leading(Integer.to_string(n), 3, "0")

  @doc """
  Reporta `cantidad` personas (`D001`...) en la zona `centro`, en estado
  `:localizada`. Devuelve `{:ok, documentos}` o el primer error.
  """
  @spec reportar_personas(struct(), pos_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def reportar_personas(usuario, cantidad) do
    1..cantidad
    |> Enum.reduce_while({:ok, []}, fn i, {:ok, documentos} ->
      documento = documento(i)

      case Emergencias.report_person(
             usuario,
             documento,
             "Persona #{i}",
             30,
             @zona,
             :localizada
           ) do
        {:ok, _persona} -> {:cont, {:ok, [documento | documentos]}}
        {:error, _razon} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, documentos} -> {:ok, Enum.reverse(documentos)}
      {:error, _razon} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrencia
  # ---------------------------------------------------------------------------

  @doc """
  Ejecuta `funcion` sobre cada elemento de `entradas`, todos a la vez (una
  tarea por elemento, `max_concurrency` igual al número de elementos), y
  devuelve los resultados en el mismo orden.
  """
  @spec en_paralelo(Enumerable.t(), (term() -> term())) :: [term()]
  def en_paralelo(entradas, funcion) when is_function(funcion, 1) do
    entradas = Enum.to_list(entradas)

    entradas
    |> Task.async_stream(funcion,
      max_concurrency: max(length(entradas), 1),
      timeout: @timeout_tarea
    )
    |> Enum.map(fn {:ok, resultado} -> resultado end)
  end

  @doc """
  Cuenta los resultados: todo `{:ok, _}` cuenta como `:ok` y cada
  `{:error, razon}` como `{:error, razon}`.

      iex> Emergencias.TestHelperApp.contar([{:ok, 1}, {:ok, 2}, {:error, :sin_stock}])
      %{:ok => 2, {:error, :sin_stock} => 1}
  """
  @spec contar([{:ok, term()} | {:error, term()}]) :: map()
  def contar(resultados) do
    Enum.frequencies_by(resultados, fn
      {:ok, _valor} -> :ok
      {:error, razon} -> {:error, razon}
    end)
  end

  @doc """
  Llama a `funcion` cada pocos milisegundos hasta que devuelve algo distinto de
  `nil` o `false`. Devuelve `{:ok, valor}` o `{:error, :tiempo_agotado}`.

  Sirve para esperar sin adivinar un `Process.sleep/1` fijo (por ejemplo, a que
  el supervisor reinicie un proceso).
  """
  @spec esperar(function(), non_neg_integer()) :: {:ok, term()} | {:error, :tiempo_agotado}
  def esperar(funcion, limite_ms \\ 2_000) when is_function(funcion, 0) do
    esperar_hasta(funcion, System.monotonic_time(:millisecond) + limite_ms)
  end

  defp esperar_hasta(funcion, limite) do
    case funcion.() do
      vacio when vacio in [nil, false] ->
        if System.monotonic_time(:millisecond) >= limite do
          {:error, :tiempo_agotado}
        else
          Process.sleep(@intervalo_espera)
          esperar_hasta(funcion, limite)
        end

      valor ->
        {:ok, valor}
    end
  end
end
