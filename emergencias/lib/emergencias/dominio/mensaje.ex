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


end
