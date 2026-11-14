defmodule Emergencias.Procesos.UsuariosServer do
  @moduledoc """
  GenServer que guarda los usuarios del sistema y su estado de conexión.

  Estado: `%{usuarios: %{username => Usuario}}`.

  Toda la lógica de la entidad vive en `Emergencias.Dominio.Usuario`; este
  proceso solo mantiene el mapa, serializa las llamadas y persiste con
  `Emergencias.Persistencia`.

  Los usuarios se guardan en `usuarios.csv` solo cuando se registra uno nuevo
  (conectar o desconectar no tocan el archivo, porque `conectado` no se
  persiste). Los usuarios cargados al iniciar empiezan desconectados.
  """

  use GenServer

  alias Emergencias.Dominio.Usuario
  alias Emergencias.Persistencia
  alias Emergencias.Util

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc "Inicia el servidor, registrado con el nombre del módulo."
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Conecta a un usuario.

  Si no existe, lo registra con `nombre_completo` igual al username, lo deja
  conectado y devuelve `{:ok, usuario, :registrado}`. Si los datos no sirven
  para crearlo devuelve el error de `Usuario.crear/5` (`:campo_vacio` o
  `:tipo_invalido`).

  Si existe, valida la contraseña y devuelve `{:ok, usuario, :autenticado}` o
  `{:error, :credenciales_invalidas}`; `tipo` y `zona` se ignoran.
  """
  @spec conectar(String.t(), String.t(), Usuario.tipo(), String.t()) ::
          {:ok, Usuario.t(), :registrado | :autenticado} | {:error, term()}
  def conectar(username, password, tipo, zona),
    do: GenServer.call(__MODULE__, {:conectar, username, password, tipo, zona})

  @doc "Desconecta a un usuario. Errores: `:no_encontrado` y `:no_conectado`."
  @spec desconectar(String.t()) :: :ok | {:error, :no_encontrado | :no_conectado}
  def desconectar(username), do: GenServer.call(__MODULE__, {:desconectar, username})

  @doc "Busca un usuario por username."
  @spec obtener(String.t()) :: {:ok, Usuario.t()} | {:error, :no_encontrado}
  def obtener(username), do: GenServer.call(__MODULE__, {:obtener, username})

  @doc "Lista los usuarios conectados, ordenados por username."
  @spec listar_conectados() :: [Usuario.t()]
  def listar_conectados, do: GenServer.call(__MODULE__, :listar_conectados)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    with {:ok, lista} <- Persistencia.cargar_usuarios(),
         {:ok, usuarios} <- indexar(lista) do
      {:ok, %{usuarios: usuarios}}
    else
      {:error, razon} -> {:stop, razon}
    end
  end

  @impl true
  def handle_call({:conectar, username, password, tipo, zona}, _from, estado) do
    clave = Util.sanitizar_texto(username)

    case Map.fetch(estado.usuarios, clave) do
      {:ok, usuario} -> autenticar(usuario, password, estado)
      :error -> registrar(clave, password, tipo, zona, estado)
    end
  end

  def handle_call({:desconectar, username}, _from, estado) do
    case Map.fetch(estado.usuarios, Util.sanitizar_texto(username)) do
      :error ->
        {:reply, {:error, :no_encontrado}, estado}

      {:ok, %Usuario{conectado: false}} ->
        {:reply, {:error, :no_conectado}, estado}

      {:ok, usuario} ->
        desconectado = Usuario.desconectar(usuario)
        {:reply, :ok, guardar_en_estado(estado, desconectado)}
    end
  end

  def handle_call({:obtener, username}, _from, estado) do
    case Map.fetch(estado.usuarios, Util.sanitizar_texto(username)) do
      {:ok, usuario} -> {:reply, {:ok, usuario}, estado}
      :error -> {:reply, {:error, :no_encontrado}, estado}
    end
  end

  def handle_call(:listar_conectados, _from, estado) do
    conectados = estado.usuarios |> lista_ordenada() |> Enum.filter(& &1.conectado)
    {:reply, conectados, estado}
  end

  # ---------------------------------------------------------------------------
  # Privadas
  # ---------------------------------------------------------------------------

  defp autenticar(usuario, password, estado) do
    case Usuario.autenticar(usuario, password) do
      {:ok, autenticado} ->
        conectado = Usuario.conectar(autenticado)
        {:reply, {:ok, conectado, :autenticado}, guardar_en_estado(estado, conectado)}

      {:error, _razon} = error ->
        {:reply, error, estado}
    end
  end

  # Si crear o guardar fallan, el estado queda igual: el usuario no se registra.
  defp registrar(clave, password, tipo, zona, estado) do
    with {:ok, nuevo} <- Usuario.crear(clave, password, clave, tipo, zona),
         usuarios = Map.put(estado.usuarios, nuevo.username, nuevo),
         :ok <- Persistencia.guardar_usuarios(lista_ordenada(usuarios)) do
      conectado = Usuario.conectar(nuevo)
      nuevo_estado = guardar_en_estado(%{estado | usuarios: usuarios}, conectado)
      {:reply, {:ok, conectado, :registrado}, nuevo_estado}
    else
      {:error, _razon} = error -> {:reply, error, estado}
    end
  end

  defp guardar_en_estado(estado, usuario),
    do: %{estado | usuarios: Map.put(estado.usuarios, usuario.username, usuario)}

  defp lista_ordenada(usuarios), do: usuarios |> Map.values() |> Enum.sort_by(& &1.username)

  defp indexar(lista) do
    Enum.reduce_while(lista, {:ok, %{}}, fn usuario, {:ok, acumulado} ->
      if Map.has_key?(acumulado, usuario.username) do
        {:halt, {:error, :id_duplicado}}
      else
        {:cont, {:ok, Map.put(acumulado, usuario.username, usuario)}}
      end
    end)
  end
end
