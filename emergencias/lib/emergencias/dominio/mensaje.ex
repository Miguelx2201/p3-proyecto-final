defmodule Emergencias.Dominio.Mensaje do
  @moduledoc """
  Mensaje que un familiar (usuario del sistema) le deja a una persona afectada.

  El `remitente` es el `username` de quien escribe y `documento_destinatario` es
  el documento de la persona afectada. Todo mensaje nace `:pendiente` y solo
  puede pasar una vez a `:entregado`:

      :pendiente -> :entregado

  Todas las funciones son puras: reciben una struct y devuelven una nueva.
  """

  alias Emergencias.{CSV, Util}

  @estados [:pendiente, :entregado]

  @archivo "mensajes.csv"
  @cabecera "id;fecha;remitente;documento;contenido;estado"

  defstruct id: nil,
            fecha: nil,
            remitente: nil,
            documento_destinatario: nil,
            contenido: nil,
            estado: :pendiente

  @type estado :: :pendiente | :entregado

  @type t :: %__MODULE__{
          id: String.t(),
          fecha: String.t(),
          remitente: String.t(),
          documento_destinatario: String.t(),
          contenido: String.t(),
          estado: estado()
        }

  @doc "Estados permitidos de un mensaje."
  def estados, do: @estados

  # ---------------------------------------------------------------------------
  # Creación y entrega
  # ---------------------------------------------------------------------------

  @doc """
  Crea un mensaje en estado `:pendiente` con la fecha actual (ISO 8601).

  Los textos se sanitizan con `Emergencias.Util.sanitizar_texto/1` (sin espacios
  en los extremos, sin `;` ni saltos de línea) y se validan después de
  sanitizar: un contenido como `" ; "` cuenta como vacío.

  Errores: `:id_vacio`, `:remitente_vacio`, `:documento_vacio`, `:contenido_vacio`.

      iex> {:ok, m} = Emergencias.Dominio.Mensaje.crear("MS001", "laura", "1094", "Estamos bien")
      iex> {m.estado, m.contenido}
      {:pendiente, "Estamos bien"}
      iex> Emergencias.Dominio.Mensaje.crear("MS001", "laura", "1094", "   ")
      {:error, :contenido_vacio}
  """
  def crear(id, remitente, documento, contenido) do
    with {:ok, id} <- validar_texto(id, :id_vacio),
         {:ok, remitente} <- validar_texto(remitente, :remitente_vacio),
         {:ok, documento} <- validar_texto(documento, :documento_vacio),
         {:ok, contenido} <- validar_texto(contenido, :contenido_vacio) do
      {:ok,
       %__MODULE__{
         id: id,
         fecha: Util.ahora(),
         remitente: remitente,
         documento_destinatario: documento,
         contenido: contenido,
         estado: :pendiente
       }}
    end
  end

  @doc """
  Marca el mensaje como entregado.

  Errores: `:ya_entregado` si ya lo estaba y `:mensaje_invalido` si el argumento
  no es un `Mensaje`.
  """
  def marcar_entregado(%__MODULE__{estado: :pendiente} = mensaje),
    do: {:ok, %{mensaje | estado: :entregado}}

  def marcar_entregado(%__MODULE__{estado: :entregado}), do: {:error, :ya_entregado}
  def marcar_entregado(_mensaje), do: {:error, :mensaje_invalido}

  # ---------------------------------------------------------------------------
  # Consulta
  # ---------------------------------------------------------------------------

  @doc """
  Mensajes cuyo destinatario tiene el `documento` dado, en el mismo orden de la
  lista. Compara igualdad exacta (con `trim` del documento buscado).

  Ignora los elementos que no son `Mensaje`. Si `mensajes` no es una lista o
  `documento` no es texto, devuelve `[]`.
  """
  def para_destinatario(mensajes, documento) when is_list(mensajes) and is_binary(documento) do
    buscado = String.trim(documento)
    for %__MODULE__{documento_destinatario: ^buscado} = mensaje <- mensajes, do: mensaje
  end

  def para_destinatario(_mensajes, _documento), do: []


  # ---------------------------------------------------------------------------
  # CSV: mensajes.csv
  # ---------------------------------------------------------------------------

  @doc "Nombre del archivo de mensajes."
  def archivo_csv, do: @archivo

  @doc "Cabecera de `mensajes.csv`."
  def cabecera_csv, do: @cabecera

  @doc """
  Línea de `mensajes.csv`: `id;fecha;remitente;documento;contenido;estado`.
  """
  def a_linea(%__MODULE__{} = mensaje) do
    CSV.unir([
      Util.sanitizar_texto(mensaje.id),
      mensaje.fecha,
      Util.sanitizar_texto(mensaje.remitente),
      Util.sanitizar_texto(mensaje.documento_destinatario),
      Util.sanitizar_texto(mensaje.contenido),
      mensaje.estado
    ])
  end

  @doc """
  Convierte una línea de `mensajes.csv` en `{:ok, mensaje}`. Una línea corrupta
  da `{:error, razon}`: `:linea_invalida` (número de campos incorrecto o no es
  texto), `:id_vacio`, `:fecha_vacia`, `:remitente_vacio`, `:documento_vacio`,
  `:contenido_vacio` o `:estado_invalido`.
  """
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [id, fecha, remitente, documento, contenido, estado] ->
        with {:ok, id} <- validar_texto(id, :id_vacio),
             {:ok, fecha} <- validar_texto(fecha, :fecha_vacia),
             {:ok, remitente} <- validar_texto(remitente, :remitente_vacio),
             {:ok, documento} <- validar_texto(documento, :documento_vacio),
             {:ok, contenido} <- validar_texto(contenido, :contenido_vacio),
             {:ok, estado} <- parsear_estado(estado) do
          {:ok,
           %__MODULE__{
             id: id,
             fecha: fecha,
             remitente: remitente,
             documento_destinatario: documento,
             contenido: contenido,
             estado: estado
           }}
        end

      _otro ->
        {:error, :linea_invalida}
    end
  end

  def de_linea(_linea), do: {:error, :linea_invalida}

end
