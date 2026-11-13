defmodule Emergencias.Dominio.Sector do
  @moduledoc """
  Sector: subdivisión de una zona que agrupa puntos de atención.

  `personas_afectadas` cuenta solo las personas propias del sector; no incluye
  las de sus puntos de atención.

  Entidad inmutable: las funciones reciben la struct y devuelven una nueva.
  Ninguna función lanza excepciones; devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Util

  @enforce_keys [:codigo, :nombre]
  defstruct [:codigo, :nombre, personas_afectadas: 0, puntos_atencion: []]

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          personas_afectadas: non_neg_integer(),
          puntos_atencion: [PuntoAtencion.t()]
        }

  @doc """
  Crea un sector sin puntos de atención validando los datos.

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

  @doc """
  Agrega un punto de atención al final de la lista del sector.

  Devuelve `{:error, :id_duplicado}` si el sector ya tiene un punto con ese
  código, y `{:error, :punto_invalido}` si el segundo argumento no es un
  `%PuntoAtencion{}`.
  """
  @spec agregar_punto(t(), PuntoAtencion.t()) :: {:ok, t()} | {:error, atom()}
  def agregar_punto(%__MODULE__{} = sector, %PuntoAtencion{} = punto) do
    if Enum.any?(sector.puntos_atencion, fn existente -> existente.codigo == punto.codigo end) do
      {:error, :id_duplicado}
    else
      {:ok, %__MODULE__{sector | puntos_atencion: sector.puntos_atencion ++ [punto]}}
    end
  end

  def agregar_punto(%__MODULE__{}, _otro), do: {:error, :punto_invalido}

  defp validar_texto(texto) when is_binary(texto) do
    if Util.vacio?(texto), do: {:error, :texto_vacio}, else: {:ok, String.trim(texto)}
  end

  defp validar_texto(_otro), do: {:error, :texto_vacio}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad >= 0,
    do: {:ok, cantidad}

  defp validar_cantidad(_otro), do: {:error, :cantidad_invalida}

  @doc """
  Convierte un sector en una línea de `sectores.csv`. No incluye sus puntos
  de atención: cada punto se guarda en su propio archivo.
  """
  def to_linea(%__MODULE__{} = sector) do
    Emergencias.CSV.unir([
      Util.sanitizar_texto(sector.codigo),
      Util.sanitizar_texto(sector.nombre),
      sector.personas_afectadas
    ])
  end

  @doc """
  Convierte una línea de `sectores.csv` en sector, siempre con
  `puntos_atencion: []`. Devuelve `{:error, :linea_invalida}` ante una línea
  corrupta (número de campos distinto de 3, texto vacío o cantidad inválida).
  """
  def de_linea(linea) when is_binary(linea) do
    with [codigo, nombre, personas] <- Emergencias.CSV.separar(linea),
         true <- Enum.all?([codigo, nombre], fn texto -> not Util.vacio?(texto) end),
         {:ok, personas} <- Util.parsear_entero_no_negativo(personas) do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         personas_afectadas: personas,
         puntos_atencion: []
       }}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}
end
