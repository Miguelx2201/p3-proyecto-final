defmodule Emergencias.Demo do
  @moduledoc """
  Scripts de demostración del sistema (los que se usan en el video).

  Se ejecutan desde la terminal:

      mix run -e "Emergencias.Demo.flujo_ejemplo()"
      mix run -e "Emergencias.Demo.conflicto_concurrente()"

  Cada paso se imprime con `IO.puts`: primero el comando equivalente de la
  consola (`usuario> comando`) y después el resultado, con el mismo texto que
  mostraría `Emergencias.CLI.Formato`. Todo pasa por la fachada `Emergencias`,
  así que se aplican los permisos y se registra la actividad como en la consola.

  ## Carpeta de datos limpia

  Las dos funciones empiezan siempre desde cero. Para lograrlo:

    1. detienen la aplicación (los servidores guardan su estado en memoria);
    2. apuntan `:data_dir` a `tmp/demo_data` y la vacían;
    3. arrancan la aplicación de nuevo (los servidores leen esa carpeta vacía);
    4. al terminar, devuelven `:data_dir` a su valor anterior y dejan la
       aplicación como estaba (corriendo o detenida).

  Así la carpeta de datos normal (`data/`) nunca se borra ni se modifica. Los
  CSV de la demostración quedan en `carpeta_datos/0` para poder mostrarlos.

  ## Usuarios de la demostración

  La contraseña de todos es `demo123`.

    * `laura` y `carlos`: coordinadores (los únicos que pueden usar
      `register_zone`, `register_resource`, `register_shelter`,
      `assign_resource` y `summary`).
    * `pedro`: voluntario (puede registrar ingresos a albergues y ejecutar
      `match_pets`).
    * `sofia` y `marta`: ciudadanas (pueden reportar personas, mascotas y
      dejar mensajes).

  Ambas funciones devuelven `:ok` o `{:error, razon}` y no lanzan excepciones.
  """

  alias Emergencias.CLI.Formato

  @app :emergencias
  @carpeta_datos "tmp/demo_data"
  @clave "demo123"
  @zona "centro"
  @documento_andres "1094567890"
  @espera_tareas 10_000

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc """
  Carpeta donde la demostración guarda sus archivos CSV.
  """
  @spec carpeta_datos() :: String.t()
  def carpeta_datos, do: @carpeta_datos

  @doc """
  Flujo completo de ejemplo, en seis pasos:

    1. Laura se conecta como coordinadora de la zona centro y la registra.
    2. Se registra `R001` con 50 litros de agua en `centro_acopio_1`.
    3. Dos coordinadores registran necesidades (30 L y 25 L) y piden
       `assign_resource` al mismo tiempo con `Task.async/1`: solo una se acepta.
    4. Se registra a Andrés como persona localizada, entra al albergue norte y
       un familiar le deja un mensaje.
    5. Se reporta una mascota perdida y otra encontrada en la misma zona y se
       ejecuta `match_pets`.
    6. Laura consulta `summary`.

  Devuelve `:ok` o `{:error, razon}` si algún paso falla (la demostración se
  detiene en ese paso).
  """
  @spec flujo_ejemplo() :: :ok | {:error, term()}
  def flujo_ejemplo do
    correr("Flujo de ejemplo", fn ->
      with {:ok, laura} <- paso_1(),
           :ok <- paso_2(laura),
           :ok <- paso_3(laura),
           {:ok, usuarios} <- paso_4(laura),
           :ok <- paso_5(usuarios) do
        paso_6(laura)
      end
    end)
  end

  @doc """
  Solo el conflicto concurrente: los pasos 2 y 3 del flujo de ejemplo.

  El paso 2 necesita una zona y un coordinador conectado, así que antes se hace
  una breve preparación (la misma conexión y registro de zona del paso 1).

  Devuelve `:ok` si exactamente una de las dos asignaciones fue aceptada, y
  `{:error, razon}` en otro caso.
  """
  @spec conflicto_concurrente() :: :ok | {:error, term()}
  def conflicto_concurrente do
    correr("Conflicto concurrente", fn ->
      titulo("Preparación: Laura se conecta y se registra la zona centro")

      with {:ok, laura} <- conectar_laura_y_registrar_zona(),
           :ok <- paso_2(laura) do
        paso_3(laura)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Pasos
  # ---------------------------------------------------------------------------

  defp paso_1 do
    titulo("Paso 1: Laura se conecta como coordinadora de la zona centro y se registra la zona")
    conectar_laura_y_registrar_zona()
  end

  defp conectar_laura_y_registrar_zona do
    with {:ok, laura} <- conectar("laura", :coordinador),
         {:ok, _zona} <-
           mostrar(
             laura,
             "register_zone #{@zona} \"Zona Centro\" alto",
             Emergencias.register_zone(laura, @zona, "Zona Centro", :alto)
           ) do
      {:ok, laura}
    end
  end

  defp paso_2(laura) do
    titulo("Paso 2: se registra R001 con 50 litros de agua en centro_acopio_1")

    with {:ok, _recurso} <-
           mostrar(
             laura,
             "register_resource R001 agua 50 litros centro_acopio_1",
             Emergencias.register_resource(laura, "R001", :agua, 50, "litros", "centro_acopio_1")
           ) do
      :ok
    end
  end

  defp paso_3(laura) do
    titulo("Paso 3: dos necesidades (30 L y 25 L) piden agua al mismo tiempo")

    with {:ok, carlos} <- conectar("carlos", :coordinador),
         {:ok, necesidad_laura} <-
           registrar_necesidad(laura, 30, :critica, "Agua para el comedor comunitario"),
         {:ok, necesidad_carlos} <-
           registrar_necesidad(carlos, 25, :alta, "Agua para el puesto de salud") do
      asignar_al_mismo_tiempo(laura, [{laura, necesidad_laura}, {carlos, necesidad_carlos}])
    end
  end

  defp paso_4(laura) do
    titulo("Paso 4: Andrés es localizado, entra al albergue norte y un familiar le escribe")

    with {:ok, _zona} <-
           mostrar(
             laura,
             "register_zone norte \"Zona Norte\" medio",
             Emergencias.register_zone(laura, "norte", "Zona Norte", :medio)
           ),
         {:ok, _albergue} <-
           mostrar(
             laura,
             "register_shelter A01 \"Albergue Norte\" norte 100",
             Emergencias.register_shelter(laura, "A01", "Albergue Norte", "norte", 100)
           ),
         {:ok, sofia} <- conectar("sofia", :ciudadano),
         {:ok, _persona} <-
           mostrar(
             sofia,
             "report_person #{@documento_andres} \"Andrés Gómez\" 34 #{@zona} localizada",
             Emergencias.report_person(
               sofia,
               @documento_andres,
               "Andrés Gómez",
               34,
               @zona,
               :localizada
             )
           ),
         {:ok, pedro} <- conectar("pedro", :voluntario),
         {:ok, _albergue} <-
           mostrar(
             pedro,
             "register_entry A01 #{@documento_andres}",
             Emergencias.register_entry(pedro, "A01", @documento_andres)
           ),
         {:ok, _personas} <-
           mostrar(
             sofia,
             "find_person #{@documento_andres}",
             Emergencias.find_person(sofia, @documento_andres)
           ),
         {:ok, marta} <- conectar("marta", :ciudadano),
         {:ok, _mensaje} <-
           mostrar(
             marta,
             "send_family_message #{@documento_andres} \"Andrés, estamos todos bien. Te esperamos.\"",
             Emergencias.send_family_message(
               marta,
               @documento_andres,
               "Andrés, estamos todos bien. Te esperamos."
             )
           ),
         {:ok, _mensajes} <-
           mostrar(
             marta,
             "list_family_messages #{@documento_andres}",
             Emergencias.list_family_messages(marta, @documento_andres)
           ) do
      {:ok, %{pedro: pedro, marta: marta}}
    end
  end

  defp paso_5(%{pedro: pedro, marta: marta}) do
    titulo("Paso 5: una mascota perdida, una encontrada en la misma zona y match_pets")

    with {:ok, _perdida} <-
           mostrar(
             marta,
             "report_pet lost perro Rocky marron mediano #{@zona} 3001112233 " <>
               "\"collar rojo mancha blanca\"",
             Emergencias.report_pet(
               marta,
               :perdida,
               "perro",
               "Rocky",
               "marron",
               :mediano,
               @zona,
               "3001112233",
               "collar rojo mancha blanca"
             )
           ),
         {:ok, _encontrada} <-
           mostrar(
             pedro,
             "report_pet found perro Rocky marron mediano #{@zona} 3009998877 " <>
               "\"collar rojo mancha blanca pecho\"",
             Emergencias.report_pet(
               pedro,
               :encontrada,
               "perro",
               "Rocky",
               "marron",
               :mediano,
               @zona,
               "3009998877",
               "collar rojo mancha blanca pecho"
             )
           ),
         {:ok, coincidencias} <- mostrar(pedro, "match_pets", Emergencias.match_pets(pedro)),
         :ok <- verificar_coincidencia(coincidencias),
         {:ok, _mascotas} <- mostrar(pedro, "list_pets", Emergencias.list_pets(pedro)) do
      :ok
    end
  end

  defp paso_6(laura) do
    titulo("Paso 6: Laura consulta el resumen general")

    with {:ok, _resumen} <- mostrar(laura, "summary", Emergencias.summary(laura)) do
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Conflicto concurrente
  # ---------------------------------------------------------------------------

  defp registrar_necesidad(usuario, cantidad, prioridad, descripcion) do
    mostrar(
      usuario,
      "register_need agua #{cantidad} #{prioridad} #{@zona} \"#{descripcion}\"",
      Emergencias.register_need(usuario, :agua, cantidad, prioridad, @zona, descripcion)
    )
  end

  # Lanza una tarea por pareja `{usuario, necesidad}` sin esperar entre ellas, y
  # solo después imprime los resultados (así la salida de las tareas no se mezcla).
  defp asignar_al_mismo_tiempo(laura, pares) do
    IO.puts("\nLos dos piden assign_resource al mismo tiempo (Task.async/1)...")

    resultados =
      pares
      |> Enum.map(fn {usuario, necesidad} ->
        Task.async(fn ->
          Emergencias.assign_resource(
            usuario,
            necesidad.id,
            necesidad.tipo,
            necesidad.cantidad_requerida
          )
        end)
      end)
      |> Task.yield_many(@espera_tareas)
      |> Enum.map(&resolver_tarea/1)

    pares
    |> Enum.zip(resultados)
    |> Enum.each(fn {{usuario, necesidad}, resultado} ->
      mostrar(
        usuario,
        "assign_resource #{necesidad.id} #{necesidad.tipo} #{necesidad.cantidad_requerida}",
        resultado
      )
    end)

    aceptadas = Enum.count(resultados, &match?({:ok, _}, &1))

    IO.puts(
      "\nAsignaciones aceptadas: #{aceptadas} de #{length(resultados)}. " <>
        "El inventario no alcanza para las dos, así que solo una puede aceptarse."
    )

    IO.puts("\nInventario y necesidades al final:")

    with {:ok, _recursos} <- mostrar(laura, "list_resources", Emergencias.list_resources(laura)),
         {:ok, _necesidades} <- mostrar(laura, "list_needs", Emergencias.list_needs(laura)) do
      verificar_una_asignacion(aceptadas)
    end
  end

  defp resolver_tarea({_tarea, {:ok, resultado}}), do: resultado
  defp resolver_tarea({_tarea, {:exit, _razon}}), do: {:error, :tarea_caida}

  defp resolver_tarea({tarea, nil}) do
    _ = Task.shutdown(tarea, :brutal_kill)
    {:error, :tiempo_agotado}
  end

  defp verificar_una_asignacion(1), do: :ok
  defp verificar_una_asignacion(_otra), do: {:error, :conflicto_inesperado}

  defp verificar_coincidencia([_ | _]), do: :ok
  defp verificar_coincidencia(_otra), do: {:error, :sin_coincidencias}

  # ---------------------------------------------------------------------------
  # Salida
  # ---------------------------------------------------------------------------

  defp conectar(nombre, tipo) do
    mostrar(
      nil,
      "connect #{nombre} #{@clave} #{tipo} #{@zona}",
      Emergencias.connect(nombre, @clave, tipo, @zona)
    )
  end

  # Imprime el comando como en la consola (`usuario> comando`), luego el
  # resultado con sangría, y devuelve el resultado sin cambios.
  defp mostrar(usuario, comando, resultado) do
    IO.puts(prompt(usuario) <> " " <> comando)
    IO.puts(sangrar(Formato.a_texto(resultado)))
    resultado
  end

  defp prompt(nil), do: "(sin sesión)>"
  defp prompt(%{username: username}), do: username <> ">"

  defp sangrar(texto) do
    texto
    |> String.split("\n")
    |> Enum.map_join("\n", fn linea -> "  " <> linea end)
  end

  defp titulo(texto), do: IO.puts("\n--- " <> texto <> " ---")

  defp correr(nombre, pasos) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("DEMOSTRACIÓN: " <> nombre)
    IO.puts("Datos de la demostración: #{@carpeta_datos} (se empieza con la carpeta vacía)")
    IO.puts(String.duplicate("=", 70))

    resultado = con_carpeta_limpia(pasos)

    case resultado do
      :ok ->
        IO.puts("\nDemostración terminada.")

      {:error, razon} ->
        IO.puts("\nLa demostración se detuvo: " <> Formato.a_texto({:error, razon}))
    end

    resultado
  end

  # ---------------------------------------------------------------------------
  # Carpeta de datos limpia
  # ---------------------------------------------------------------------------

  # Ejecuta `pasos` con la aplicación recién arrancada sobre una carpeta vacía y
  # lo deja todo como estaba, incluso si `pasos` falla.
  defp con_carpeta_limpia(pasos) do
    estaba_arriba? = app_corriendo?()
    entorno_anterior = Application.fetch_env(@app, :data_dir)
    nivel_anterior = Logger.level()

    # Detener la aplicación escribe un aviso en el log que ensuciaría la salida.
    Logger.configure(level: :warning)

    try do
      with :ok <- detener_app(),
           :ok <- Application.put_env(@app, :data_dir, @carpeta_datos),
           :ok <- preparar_carpeta(),
           :ok <- iniciar_app() do
        pasos.()
      end
    after
      restaurar(entorno_anterior, estaba_arriba?)
      Logger.configure(level: nivel_anterior)
    end
  end

  defp restaurar(entorno_anterior, estaba_arriba?) do
    _ = detener_app()

    case entorno_anterior do
      {:ok, carpeta} -> Application.put_env(@app, :data_dir, carpeta)
      :error -> Application.delete_env(@app, :data_dir)
    end

    if estaba_arriba?, do: iniciar_app()
  end

  defp app_corriendo? do
    Enum.any?(Application.started_applications(), fn {app, _descripcion, _version} ->
      app == @app
    end)
  end

  defp detener_app do
    case Application.stop(@app) do
      :ok -> :ok
      {:error, {:not_started, @app}} -> :ok
      {:error, _razon} -> {:error, :no_se_pudo_detener}
    end
  end

  defp iniciar_app do
    case Application.ensure_all_started(@app) do
      {:ok, _apps} -> :ok
      {:error, _razon} -> {:error, :no_se_pudo_iniciar}
    end
  end

  # También crea `albergues/`: los albergues guardan sus archivos en esa subcarpeta.
  defp preparar_carpeta do
    with {:ok, _borrados} <- File.rm_rf(@carpeta_datos),
         :ok <- File.mkdir_p(Path.join(@carpeta_datos, "albergues")) do
      :ok
    else
      _error -> {:error, :carpeta_no_preparada}
    end
  end
end
