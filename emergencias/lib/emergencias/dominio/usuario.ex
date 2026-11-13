defmodule Emergencias.Dominio.Usuario do
  @moduledoc """
  Entidad Usuario: persona que usa el sistema desde la consola.

  Es una struct inmutable; todas las funciones reciben un usuario y devuelven
  uno nuevo. Ninguna función lanza excepciones.

  La contraseña nunca se guarda en texto plano: se almacena su hash SHA-256
  en hexadecimal. El campo `conectado` es estado de sesión: no se persiste y
  al cargar desde CSV siempre vale `false`.
  """

  alias Emergencias.CSV
  alias Emergencias.Util

  @tipos [:ciudadano, :voluntario, :coordinador, :administrador]
  @cabecera "username;password_hash;nombre_completo;tipo;zona"

  defstruct username: nil,
            password_hash: nil,
            nombre_completo: nil,
            tipo: nil,
            zona: nil,
            conectado: false

  @type tipo :: :ciudadano | :voluntario | :coordinador | :administrador

  @type t :: %__MODULE__{
          username: String.t(),
          password_hash: String.t(),
          nombre_completo: String.t(),
          tipo: tipo(),
          zona: String.t(),
          conectado: boolean()
        }

  @doc "Tipos de usuario permitidos."
  def tipos, do: @tipos

  @doc "Cabecera del archivo `usuarios.csv`."
  def cabecera, do: @cabecera

  @doc """
  Crea un usuario con la contraseña ya convertida en hash y `conectado: false`.

  Devuelve `{:ok, usuario}` o `{:error, :campo_vacio | :tipo_invalido}`.
  Los textos vacíos, solo con espacios o que no sean texto dan `:campo_vacio`
  (se revisa antes que el tipo). `username`, `nombre_completo` y `zona` se
  sanitizan (se quitan `;` y saltos de línea) para no romper el CSV; la
  contraseña se usa tal cual, sin recortar.
  """
  def crear(username, password, nombre_completo, tipo, zona) do
    username = Util.sanitizar_texto(username)
    nombre_completo = Util.sanitizar_texto(nombre_completo)
    zona = Util.sanitizar_texto(zona)

    with :ok <- validar_textos([username, password, nombre_completo, zona]),
         :ok <- validar_tipo(tipo) do
      {:ok,
       %__MODULE__{
         username: username,
         password_hash: hashear(password),
         nombre_completo: nombre_completo,
         tipo: tipo,
         zona: zona,
         conectado: false
       }}
    end
  end

  @doc """
  Verifica la contraseña. Devuelve `{:ok, usuario}` si coincide o
  `{:error, :credenciales_invalidas}` si no (también si no es texto).
  No cambia el campo `conectado`; eso lo hace `conectar/1`.
  """
  def autenticar(%__MODULE__{password_hash: hash} = usuario, password)
      when is_binary(password) do
    if hashear(password) == hash do
      {:ok, usuario}
    else
      {:error, :credenciales_invalidas}
    end
  end

  def autenticar(%__MODULE__{}, _password), do: {:error, :credenciales_invalidas}

  @doc "Devuelve el usuario con `conectado: true` (si ya lo estaba, no cambia)."
  def conectar(%__MODULE__{} = usuario), do: %{usuario | conectado: true}

  @doc "Devuelve el usuario con `conectado: false` (si ya lo estaba, no cambia)."
  def desconectar(%__MODULE__{} = usuario), do: %{usuario | conectado: false}

  @doc """
  Convierte el usuario en una línea de `usuarios.csv` (sin salto de línea).
  El campo `conectado` no se guarda.
  """
  def to_linea(%__MODULE__{} = usuario) do
    CSV.unir([
      Util.sanitizar_texto(usuario.username),
      usuario.password_hash,
      Util.sanitizar_texto(usuario.nombre_completo),
      Atom.to_string(usuario.tipo),
      Util.sanitizar_texto(usuario.zona)
    ])
  end

  @doc """
  Convierte una línea de `usuarios.csv` en usuario, siempre con
  `conectado: false`. Devuelve `{:error, :linea_invalida}` ante una línea
  corrupta (número de campos distinto de 5, campo vacío o tipo desconocido).
  """
  def de_linea(linea) when is_binary(linea) do
    with [username, password_hash, nombre_completo, tipo, zona] <- CSV.separar(linea),
         true <- Enum.all?([username, password_hash, nombre_completo, zona], &texto_valido?/1),
         {:ok, tipo} <- Util.parsear_enum(tipo, @tipos) do
      {:ok,
       %__MODULE__{
         username: username,
         password_hash: password_hash,
         nombre_completo: nombre_completo,
         tipo: tipo,
         zona: zona,
         conectado: false
       }}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}

  # ---------------------------------------------------------------------------
  # Privadas
  # ---------------------------------------------------------------------------

  defp hashear(password), do: :crypto.hash(:sha256, password) |> Base.encode16()

  defp texto_valido?(texto), do: is_binary(texto) and not Util.vacio?(texto)

  defp validar_textos(textos) do
    if Enum.all?(textos, &texto_valido?/1), do: :ok, else: {:error, :campo_vacio}
  end

  defp validar_tipo(tipo) when tipo in @tipos, do: :ok
  defp validar_tipo(_tipo), do: {:error, :tipo_invalido}
end
