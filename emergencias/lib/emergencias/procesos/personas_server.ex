defmodule Emergencias.Procesos.PersonasServer do
  @moduledoc """
  Proceso dueño de las personas afectadas y de los mensajes que los familiares
  les dejan.

  Estado: `%{personas: %{documento => Persona}, mensajes: %{id => Mensaje}, contador_msg: n}`.
  Los ids de mensaje son `MS001`, `MS002`...

  Al arrancar carga `personas.csv`, `historial_personas.csv` y `mensajes.csv`
  con `Emergencias.Persistencia`. Después de cada cambio guarda los archivos
  afectados; si guardar falla, el cambio se descarta (el estado en memoria no
  cambia) y se devuelve `{:error, razon}`.

  Este proceso es el único escritor de esos tres archivos. Ninguna función
  lanza excepciones: devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  use GenServer

  alias Emergencias.Dominio.{Mensaje, Persona}
  alias Emergencias.{Persistencia, Util}

  @prefijo_id "MS"
  @digitos_id 3

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc "Arranca el proceso con el nombre del módulo."
  def start_link(_opciones \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Registra una persona. Devuelve `{:ok, persona}`.

  Errores: `:id_duplicado` si el documento ya existe, los de
  `Emergencias.Dominio.Persona.crear/6` y los de guardar en disco.
  """
  def reportar(documento, nombre, edad, zona, estado, usuario) do
    GenServer.call(__MODULE__, {:reportar, documento, nombre, edad, zona, estado, usuario})
  end

  @doc """
  Personas que cumplen todos los `filtros` (ver `Emergencias.Dominio.Persona.coincide?/2`),
  ordenadas por documento. Devuelve `{:ok, lista}` o `{:error, :filtros_invalidos}`
  si `filtros` no es una lista.
  """
  def buscar(filtros), do: GenServer.call(__MODULE__, {:buscar, filtros})

  @doc "Devuelve `{:ok, persona}` o `{:error, :persona_no_encontrada}`."
  def obtener(documento), do: GenServer.call(__MODULE__, {:obtener, documento})

  @doc """
  Cambia el estado de una persona. Devuelve `{:ok, persona}`.

  Errores: `:persona_no_encontrada`, los de
  `Emergencias.Dominio.Persona.cambiar_estado/3` y los de guardar en disco.
  """
  def cambiar_estado(documento, nuevo, usuario) do
    GenServer.call(__MODULE__, {:cambiar_estado, documento, nuevo, usuario})
  end

  @doc """
  Historial de la persona, el cambio más reciente primero.
  Devuelve `{:ok, historial}` o `{:error, :persona_no_encontrada}`.
  """
  def historial(documento), do: GenServer.call(__MODULE__, {:historial, documento})

  @doc """
  Deja un mensaje `:pendiente` para una persona. Devuelve `{:ok, mensaje}`.

  Errores: `:persona_no_encontrada` si el documento no está registrado, los de
  `Emergencias.Dominio.Mensaje.crear/4` y los de guardar en disco.
  """
  def enviar_mensaje(remitente, documento, contenido) do
    GenServer.call(__MODULE__, {:enviar_mensaje, remitente, documento, contenido})
  end

  @doc """
  Mensajes dirigidos al documento, en orden de id. Devuelve `{:ok, lista}`
  (vacía si no hay mensajes).
  """
  def listar_mensajes(documento), do: GenServer.call(__MODULE__, {:listar_mensajes, documento})

  @doc """
  Marca un mensaje como entregado. Devuelve `{:ok, mensaje}`.

  Errores: `:mensaje_no_encontrado`, `:ya_entregado` y los de guardar en disco.
  """
  def marcar_entregado(id), do: GenServer.call(__MODULE__, {:marcar_entregado, id})

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    with {:ok, personas} <- Persistencia.cargar_personas(),
         {:ok, mensajes} <- Persistencia.cargar_mensajes() do
      {:ok,
       %{
         personas: Map.new(personas, fn persona -> {persona.documento, persona} end),
         mensajes: Map.new(mensajes, fn mensaje -> {mensaje.id, mensaje} end),
         contador_msg: ultimo_numero(mensajes)
       }}
    else
      {:error, razon} -> {:stop, razon}
    end
  end

  @impl true
  def handle_call({:reportar, documento, nombre, edad, zona, estado, usuario}, _from, datos) do
    with {:ok, persona} <- Persona.crear(documento, nombre, edad, zona, estado, usuario),
         :ok <- validar_nueva(datos, persona),
         nuevos = guardar_persona_en(datos, persona),
         :ok <- guardar_personas(nuevos) do
      {:reply, {:ok, persona}, nuevos}
    else
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  def handle_call({:buscar, filtros}, _from, datos) when is_list(filtros) do
    encontradas =
      datos.personas
      |> Map.values()
      |> Enum.filter(fn persona -> Persona.coincide?(persona, filtros) end)
      |> Enum.sort_by(fn persona -> persona.documento end)

    {:reply, {:ok, encontradas}, datos}
  end

  def handle_call({:buscar, _filtros}, _from, datos),
    do: {:reply, {:error, :filtros_invalidos}, datos}

  def handle_call({:obtener, documento}, _from, datos),
    do: {:reply, buscar_persona(datos, documento), datos}

  def handle_call({:cambiar_estado, documento, nuevo, usuario}, _from, datos) do
    with {:ok, persona} <- buscar_persona(datos, documento),
         {:ok, actualizada} <- Persona.cambiar_estado(persona, nuevo, usuario),
         nuevos = guardar_persona_en(datos, actualizada),
         :ok <- guardar_personas(nuevos) do
      {:reply, {:ok, actualizada}, nuevos}
    else
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  def handle_call({:historial, documento}, _from, datos) do
    case buscar_persona(datos, documento) do
      {:ok, persona} -> {:reply, {:ok, persona.historial}, datos}
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  def handle_call({:enviar_mensaje, remitente, documento, contenido}, _from, datos) do
    numero = datos.contador_msg + 1

    with {:ok, mensaje} <- Mensaje.crear(formatear_id(numero), remitente, documento, contenido),
         {:ok, _persona} <- buscar_persona(datos, mensaje.documento_destinatario),
         nuevos = guardar_mensaje_en(datos, mensaje, numero),
         :ok <- guardar_mensajes(nuevos) do
      {:reply, {:ok, mensaje}, nuevos}
    else
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  def handle_call({:listar_mensajes, documento}, _from, datos) do
    ordenados = ordenar_mensajes(datos.mensajes)
    {:reply, {:ok, Mensaje.para_destinatario(ordenados, documento)}, datos}
  end

  def handle_call({:marcar_entregado, id}, _from, datos) do
    with {:ok, mensaje} <- buscar_mensaje(datos, id),
         {:ok, entregado} <- Mensaje.marcar_entregado(mensaje),
         nuevos = guardar_mensaje_en(datos, entregado, datos.contador_msg),
         :ok <- guardar_mensajes(nuevos) do
      {:reply, {:ok, entregado}, nuevos}
    else
      {:error, razon} -> {:reply, {:error, razon}, datos}
    end
  end

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp validar_nueva(datos, persona) do
    if Map.has_key?(datos.personas, persona.documento), do: {:error, :id_duplicado}, else: :ok
  end

  defp guardar_persona_en(datos, persona),
    do: %{datos | personas: Map.put(datos.personas, persona.documento, persona)}

  defp guardar_mensaje_en(datos, mensaje, contador),
    do: %{datos | mensajes: Map.put(datos.mensajes, mensaje.id, mensaje), contador_msg: contador}

  # Los documentos y los ids se guardan ya sanitizados (sin espacios en los
  # extremos ni `;`), así que se buscan con la misma normalización.
  defp buscar_persona(datos, documento) do
    case Map.fetch(datos.personas, normalizar(documento)) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, :persona_no_encontrada}
    end
  end

  defp buscar_mensaje(datos, id) do
    case Map.fetch(datos.mensajes, normalizar(id)) do
      {:ok, mensaje} -> {:ok, mensaje}
      :error -> {:error, :mensaje_no_encontrado}
    end
  end

  defp normalizar(texto) when is_binary(texto), do: Util.sanitizar_texto(texto)
  defp normalizar(_otro), do: nil

  defp guardar_personas(datos) do
    datos.personas
    |> Map.values()
    |> Enum.sort_by(fn persona -> persona.documento end)
    |> Persistencia.guardar_personas()
  end

  defp guardar_mensajes(datos) do
    datos.mensajes
    |> ordenar_mensajes()
    |> Persistencia.guardar_mensajes()
  end

  defp ordenar_mensajes(mensajes) do
    mensajes
    |> Map.values()
    |> Enum.sort_by(fn mensaje -> {numero_id(mensaje.id), mensaje.id} end)
  end

  defp formatear_id(numero) do
    @prefijo_id <> String.pad_leading(Integer.to_string(numero), @digitos_id, "0")
  end

  # Número de un id `MS007` (7). Un id con otro formato cuenta como 0.
  defp numero_id(@prefijo_id <> resto) do
    case Integer.parse(resto) do
      {numero, ""} -> numero
      _ -> 0
    end
  end

  defp numero_id(_otro), do: 0

  defp ultimo_numero(mensajes) do
    mensajes
    |> Enum.map(fn mensaje -> numero_id(mensaje.id) end)
    |> Enum.max(fn -> 0 end)
  end
end
