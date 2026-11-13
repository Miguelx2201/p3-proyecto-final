defmodule Emergencias.Dominio.Movimiento do
  @moduledoc """
  Registro de un cambio en el inventario de un recurso.

  `nuevo/5` deja el `id` en `nil`: lo asigna el servidor de recursos antes de
  guardar el movimiento.

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.CSV
  alias Emergencias.Util

  @tipos [:entrada, :salida, :asignacion, :transferencia_salida, :transferencia_entrada]

  @cabecera "id;recurso_id;tipo;cantidad;fecha;usuario;referencia"

  @enforce_keys [:recurso_id, :tipo, :cantidad, :fecha, :usuario]
  defstruct [:id, :recurso_id, :tipo, :cantidad, :fecha, :usuario, :referencia]

  @type tipo ::
          :entrada | :salida | :asignacion | :transferencia_salida | :transferencia_entrada

  @type t :: %__MODULE__{
          id: String.t() | nil,
          recurso_id: String.t(),
          tipo: tipo(),
          cantidad: pos_integer(),
          fecha: String.t(),
          usuario: String.t(),
          referencia: String.t() | nil
        }

  @doc "Tipos válidos de movimiento."
  def tipos, do: @tipos

  @doc "Cabecera del archivo `movimientos.csv`."
  def cabecera, do: @cabecera

  @doc """
  Crea un movimiento con la fecha actual y `id` en `nil`.

  `referencia` es el id de una necesidad, un centro de destino, o `nil`
  (un texto vacío también se guarda como `nil`).

  Errores: `:texto_vacio`, `:tipo_invalido`, `:cantidad_invalida`,
  `:referencia_invalida`.
  """
  def nuevo(recurso_id, tipo, cantidad, usuario, referencia) do
    with {:ok, recurso_id} <- validar_texto(recurso_id),
         {:ok, usuario} <- validar_texto(usuario),
         {:ok, tipo} <- validar_tipo(tipo),
         {:ok, cantidad} <- validar_cantidad(cantidad),
         {:ok, referencia} <- validar_referencia(referencia) do
      {:ok,
       %__MODULE__{
         id: nil,
         recurso_id: recurso_id,
         tipo: tipo,
         cantidad: cantidad,
         fecha: Util.ahora(),
         usuario: usuario,
         referencia: referencia
       }}
    end
  end

  @doc """
  Convierte el movimiento en una línea de `movimientos.csv`
  (`id;recurso_id;tipo;cantidad;fecha;usuario;referencia`).

  Un `id` o una `referencia` en `nil` se escriben como campo vacío.
  """
  def a_linea(%__MODULE__{} = movimiento) do
    CSV.unir([
      Util.sanitizar_texto(movimiento.id),
      Util.sanitizar_texto(movimiento.recurso_id),
      movimiento.tipo,
      movimiento.cantidad,
      Util.sanitizar_texto(movimiento.fecha),
      Util.sanitizar_texto(movimiento.usuario),
      Util.sanitizar_texto(movimiento.referencia)
    ])
  end

  @doc """
  Convierte una línea de `movimientos.csv` en un movimiento.

  El `id` es obligatorio al leer (un movimiento guardado ya tiene id). Una línea
  corrupta devuelve `{:error, razon}` y nunca lanza excepción.
  """
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [id, recurso_id, tipo, cantidad, fecha, usuario, referencia] ->
        with {:ok, id} <- validar_texto(id),
             {:ok, recurso_id} <- validar_texto(recurso_id),
             {:ok, tipo} <- Util.parsear_enum(tipo, @tipos),
             {:ok, cantidad} <- Util.parsear_entero(cantidad),
             {:ok, cantidad} <- validar_cantidad(cantidad),
             {:ok, fecha} <- validar_fecha(fecha),
             {:ok, usuario} <- validar_texto(usuario),
             {:ok, referencia} <- validar_referencia(referencia) do
          {:ok,
           %__MODULE__{
             id: id,
             recurso_id: recurso_id,
             tipo: tipo,
             cantidad: cantidad,
             fecha: fecha,
             usuario: usuario,
             referencia: referencia
           }}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}

  defp validar_texto(texto) do
    limpio = Util.sanitizar_texto(texto)
    if Util.vacio?(limpio), do: {:error, :texto_vacio}, else: {:ok, limpio}
  end

  defp validar_tipo(tipo) when tipo in @tipos, do: {:ok, tipo}
  defp validar_tipo(_otro), do: {:error, :tipo_invalido}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad > 0, do: {:ok, cantidad}
  defp validar_cantidad(_otra), do: {:error, :cantidad_invalida}

  defp validar_referencia(nil), do: {:ok, nil}

  defp validar_referencia(referencia) when is_binary(referencia) do
    limpia = Util.sanitizar_texto(referencia)
    if limpia == "", do: {:ok, nil}, else: {:ok, limpia}
  end

  defp validar_referencia(_otra), do: {:error, :referencia_invalida}

  defp validar_fecha(fecha) do
    case DateTime.from_iso8601(fecha) do
      {:ok, _fecha, _desfase} -> {:ok, fecha}
      {:error, _razon} -> {:error, :fecha_invalida}
    end
  end
end
