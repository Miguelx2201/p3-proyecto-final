defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  Zona: área geográfica afectada por el terremoto, identificada por su código
  (por ejemplo `centro`).

  `personas_afectadas` es una estimación de la zona y es independiente de las
  cantidades de sus sectores: no se suman ni se validan entre sí.

  Las relaciones con albergues, necesidades, recursos y reportes no se guardan
  aquí: cada una de esas entidades guarda el código de su zona.

  Entidad inmutable: las funciones reciben la struct y devuelven una nueva.
  Ninguna función lanza excepciones; devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.Dominio.Sector
  alias Emergencias.Util

  @niveles [:critico, :alto, :medio, :bajo]

  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct [:codigo, :nombre, :nivel, personas_afectadas: 0, sectores: []]

  @type nivel :: :critico | :alto | :medio | :bajo
  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          nivel: nivel(),
          personas_afectadas: non_neg_integer(),
          sectores: [Sector.t()]
        }

  @doc """
  Crea una zona sin sectores validando los datos.

  Errores posibles (se revisan en este orden): `{:error, :texto_vacio}` si el
  código o el nombre no son texto o están vacíos, `{:error, :nivel_invalido}` si
  el nivel no es `:critico`, `:alto`, `:medio` o `:bajo`, y
  `{:error, :cantidad_invalida}` si `personas` no es un entero mayor o igual a 0.
  """
  @spec crear(term(), term(), term(), term()) :: {:ok, t()} | {:error, atom()}
  def crear(codigo, nombre, nivel, personas \\ 0) do
    with {:ok, codigo} <- validar_texto(codigo),
         {:ok, nombre} <- validar_texto(nombre),
         {:ok, nivel} <- validar_nivel(nivel),
         {:ok, personas} <- validar_cantidad(personas) do
      {:ok,
       %__MODULE__{codigo: codigo, nombre: nombre, nivel: nivel, personas_afectadas: personas}}
    end
  end

  @doc """
  Agrega un sector al final de la lista de la zona.

  Devuelve `{:error, :id_duplicado}` si la zona ya tiene un sector con ese
  código, y `{:error, :sector_invalido}` si el segundo argumento no es un
  `%Sector{}`.
  """
  @spec agregar_sector(t(), Sector.t()) :: {:ok, t()} | {:error, atom()}
  def agregar_sector(%__MODULE__{} = zona, %Sector{} = sector) do
    if Enum.any?(zona.sectores, fn existente -> existente.codigo == sector.codigo end) do
      {:error, :id_duplicado}
    else
      {:ok, %__MODULE__{zona | sectores: zona.sectores ++ [sector]}}
    end
  end

  def agregar_sector(%__MODULE__{}, _otro), do: {:error, :sector_invalido}

  @doc """
  Cambia el nivel de afectación de la zona.

  Devuelve `{:error, :nivel_invalido}` si el nivel no está permitido. Cambiar al
  mismo nivel que ya tiene es válido y devuelve la zona igual.
  """
  @spec cambiar_nivel(t(), term()) :: {:ok, t()} | {:error, atom()}
  def cambiar_nivel(%__MODULE__{} = zona, nivel) do
    with {:ok, nivel} <- validar_nivel(nivel) do
      {:ok, %__MODULE__{zona | nivel: nivel}}
    end
  end

  @doc """
  Actualiza la estimación de personas afectadas de la zona.

  Devuelve `{:error, :cantidad_invalida}` si `cantidad` no es un entero mayor o
  igual a 0.
  """
  @spec actualizar_personas(t(), term()) :: {:ok, t()} | {:error, atom()}
  def actualizar_personas(%__MODULE__{} = zona, cantidad) do
    with {:ok, cantidad} <- validar_cantidad(cantidad) do
      {:ok, %__MODULE__{zona | personas_afectadas: cantidad}}
    end
  end

  defp validar_texto(texto) when is_binary(texto) do
    if Util.vacio?(texto), do: {:error, :texto_vacio}, else: {:ok, String.trim(texto)}
  end

  defp validar_texto(_otro), do: {:error, :texto_vacio}

  defp validar_nivel(nivel) when nivel in @niveles, do: {:ok, nivel}
  defp validar_nivel(_otro), do: {:error, :nivel_invalido}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad >= 0,
    do: {:ok, cantidad}

  defp validar_cantidad(_otro), do: {:error, :cantidad_invalida}

  @doc """
  Convierte una zona en una línea de `zonas.csv`. No incluye sus sectores:
  cada sector se guarda en su propio archivo.
  """
  def to_linea(%__MODULE__{} = zona) do
    Emergencias.CSV.unir([
      Util.sanitizar_texto(zona.codigo),
      Util.sanitizar_texto(zona.nombre),
      Atom.to_string(zona.nivel),
      zona.personas_afectadas
    ])
  end

  @doc """
  Convierte una línea de `zonas.csv` en zona, siempre con `sectores: []`.
  Devuelve `{:error, :linea_invalida}` ante una línea corrupta (número de
  campos distinto de 4, texto vacío, nivel desconocido o cantidad inválida).
  """
  def de_linea(linea) when is_binary(linea) do
    with [codigo, nombre, nivel, personas] <- Emergencias.CSV.separar(linea),
         true <- Enum.all?([codigo, nombre], fn texto -> not Util.vacio?(texto) end),
         {:ok, nivel} <- Util.parsear_enum(nivel, @niveles),
         {:ok, personas} <- Util.parsear_entero_no_negativo(personas) do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         nivel: nivel,
         personas_afectadas: personas,
         sectores: []
       }}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}
end
