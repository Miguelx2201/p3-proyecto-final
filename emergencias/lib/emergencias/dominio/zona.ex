defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  Zona: área geográfica afectada por el terremoto, identificada por su código
  (por ejemplo `centro`).

  `personas_afectadas` es una estimación de la zona y es independiente de las
  cantidades de sus sectores: no se suman ni se validan entre sí.

  Las funciones `total_personas/1`, `buscar_nodo/2`, `aplanar/1` y
  `estadisticas/1` recorren la jerarquía Zona → Sectores → Puntos de atención
  con recursión escrita a mano (pattern matching sobre `[]` y `[cabeza | resto]`)
  y con acumulador, de modo que cada llamada recursiva queda en posición de cola.

  Las relaciones con albergues, necesidades, recursos y reportes no se guardan
  aquí: cada una de esas entidades guarda el código de su zona.

  Entidad inmutable: las funciones reciben la struct y devuelven una nueva.
  Ninguna función lanza excepciones; devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.Dominio.PuntoAtencion
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

  @doc """
  Suma las personas de todos los sectores y de todos los puntos de atención.

  Cada nodo cuenta solo las suyas. No incluye `personas_afectadas` de la zona,
  que es una estimación independiente (ver `estadisticas/1`, clave `estimadas`).
  """
  @spec total_personas(t()) :: non_neg_integer()
  def total_personas(%__MODULE__{sectores: sectores}), do: sumar_sectores(sectores, 0)

  @doc """
  Busca recursivamente un sector o un punto de atención por su código.

  Devuelve `{:ok, {:sector, sector}}`, `{:ok, {:punto, punto}}` o
  `{:error, :no_encontrado}`. El recorrido es en profundidad y en el orden de
  las listas: cada sector se compara antes que sus puntos, y los puntos de un
  sector antes que el sector siguiente. Si un código se repite, gana el primero
  que se encuentre en ese orden.
  """
  @spec buscar_nodo(t(), term()) ::
          {:ok, {:sector, Sector.t()}} | {:ok, {:punto, PuntoAtencion.t()}} | {:error, atom()}
  def buscar_nodo(%__MODULE__{sectores: sectores}, codigo),
    do: buscar_en_sectores(sectores, codigo)

  @doc """
  Aplana la jerarquía en una lista de tuplas `{tipo, codigo, nombre, personas}`
  con `tipo` igual a `:sector` o `:punto`.

  El orden es: un sector seguido de sus puntos, luego el siguiente sector, y así
  sucesivamente. Una zona sin sectores devuelve `[]`.
  """
  @spec aplanar(t()) :: [{:sector | :punto, String.t(), String.t(), non_neg_integer()}]
  def aplanar(%__MODULE__{sectores: sectores}), do: aplanar_sectores(sectores, [])

  @doc """
  Calcula estadísticas de la zona recorriendo la jerarquía una sola vez.

  Devuelve un mapa con `total_personas` (suma de sectores y puntos),
  `estimadas` (el campo `personas_afectadas` de la zona), `num_sectores`,
  `num_puntos` y `por_sector`, una lista `%{codigo: codigo, total: total}` en el
  orden de los sectores donde `total` suma las personas del sector y las de sus
  puntos.
  """
  @spec estadisticas(t()) :: %{
          total_personas: non_neg_integer(),
          estimadas: non_neg_integer(),
          num_sectores: non_neg_integer(),
          num_puntos: non_neg_integer(),
          por_sector: [%{codigo: String.t(), total: non_neg_integer()}]
        }
  def estadisticas(%__MODULE__{} = zona) do
    inicial = %{total_personas: 0, num_sectores: 0, num_puntos: 0, por_sector: []}
    acumulado = estadisticas_sectores(zona.sectores, inicial)

    %{
      total_personas: acumulado.total_personas,
      estimadas: zona.personas_afectadas,
      num_sectores: acumulado.num_sectores,
      num_puntos: acumulado.num_puntos,
      por_sector: Enum.reverse(acumulado.por_sector)
    }
  end

  # total_personas/1

  defp sumar_sectores([], acumulado), do: acumulado

  defp sumar_sectores([sector | resto], acumulado) do
    con_sector = acumulado + sector.personas_afectadas
    sumar_sectores(resto, sumar_puntos(sector.puntos_atencion, con_sector))
  end

  defp sumar_puntos([], acumulado), do: acumulado

  defp sumar_puntos([punto | resto], acumulado),
    do: sumar_puntos(resto, acumulado + punto.personas_afectadas)

  # buscar_nodo/2

  defp buscar_en_sectores([], _codigo), do: {:error, :no_encontrado}

  defp buscar_en_sectores([%Sector{codigo: codigo} = sector | _resto], codigo),
    do: {:ok, {:sector, sector}}

  defp buscar_en_sectores([sector | resto], codigo) do
    case buscar_en_puntos(sector.puntos_atencion, codigo) do
      {:ok, _nodo} = encontrado -> encontrado
      {:error, :no_encontrado} -> buscar_en_sectores(resto, codigo)
    end
  end

  defp buscar_en_puntos([], _codigo), do: {:error, :no_encontrado}

  defp buscar_en_puntos([%PuntoAtencion{codigo: codigo} = punto | _resto], codigo),
    do: {:ok, {:punto, punto}}

  defp buscar_en_puntos([_punto | resto], codigo), do: buscar_en_puntos(resto, codigo)

  # aplanar/1

  defp aplanar_sectores([], acumulado), do: Enum.reverse(acumulado)

  defp aplanar_sectores([sector | resto], acumulado) do
    con_sector = [{:sector, sector.codigo, sector.nombre, sector.personas_afectadas} | acumulado]
    aplanar_sectores(resto, aplanar_puntos(sector.puntos_atencion, con_sector))
  end

  defp aplanar_puntos([], acumulado), do: acumulado

  defp aplanar_puntos([punto | resto], acumulado) do
    aplanar_puntos(resto, [
      {:punto, punto.codigo, punto.nombre, punto.personas_afectadas} | acumulado
    ])
  end

  # estadisticas/1

  defp estadisticas_sectores([], acumulado), do: acumulado

  defp estadisticas_sectores([sector | resto], acumulado) do
    total = sumar_puntos(sector.puntos_atencion, sector.personas_afectadas)

    actualizado = %{
      acumulado
      | total_personas: acumulado.total_personas + total,
        num_sectores: acumulado.num_sectores + 1,
        num_puntos: contar_puntos(sector.puntos_atencion, acumulado.num_puntos),
        por_sector: [%{codigo: sector.codigo, total: total} | acumulado.por_sector]
    }

    estadisticas_sectores(resto, actualizado)
  end

  defp contar_puntos([], acumulado), do: acumulado
  defp contar_puntos([_punto | resto], acumulado), do: contar_puntos(resto, acumulado + 1)

  defp validar_texto(texto) when is_binary(texto) do
    if Util.vacio?(texto), do: {:error, :texto_vacio}, else: {:ok, String.trim(texto)}
  end

  defp validar_texto(_otro), do: {:error, :texto_vacio}

  defp validar_nivel(nivel) when nivel in @niveles, do: {:ok, nivel}
  defp validar_nivel(_otro), do: {:error, :nivel_invalido}

  defp validar_cantidad(cantidad) when is_integer(cantidad) and cantidad >= 0,
    do: {:ok, cantidad}

  defp validar_cantidad(_otro), do: {:error, :cantidad_invalida}
end
