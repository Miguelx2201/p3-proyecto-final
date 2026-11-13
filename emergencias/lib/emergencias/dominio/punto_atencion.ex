defmodule Emergencias.Dominio.PuntoAtencion do
  @moduledoc """
  Punto de atención: lugar concreto dentro de un sector donde se atiende a las
  personas afectadas.

  Entidad inmutable: las funciones reciben la struct y devuelven una nueva.
  Ninguna función lanza excepciones; devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.Util

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, personas_afectadas: 0]

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          personas_afectadas: non_neg_integer()
        }

  @doc """
  Crea un punto de atención validando los datos.

  Errores posibles (se revisan en este orden): `{:error, :texto_vacio}` si el
  código o el nombre no son texto o están vacíos, y `{:error, :cantidad_invalida}`
  si `personas_afectadas` no es un entero mayor o igual a 0.
  """
  @spec crear(term(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def crear(codigo, nombre, personas_afectadas) do
    with {:ok, codigo} <- validar_texto(codigo),
         {:ok, nombre} <- validar_texto(nombre),
         {:ok, personas_afectadas} <- validar_cantidad(personas_afectadas) do
      {:ok, %__MODULE__{codigo: codigo, nombre: nombre, personas_afectadas: personas_afectadas}}
    end
  end

  defp validar_texto(texto) when is_binary(texto) do
    if Util.vacio?(texto), do: {:error, :texto_vacio}, else: {:ok, String.trim(texto)}
  end

  defp validar_texto(_otro), do: {:error, :texto_vacio}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad >= 0,
    do: {:ok, cantidad}

  defp validar_cantidad(_otro), do: {:error, :cantidad_invalida}
end
