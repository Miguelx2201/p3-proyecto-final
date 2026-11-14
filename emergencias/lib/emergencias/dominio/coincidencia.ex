defmodule Emergencias.Dominio.Coincidencia do
  @moduledoc """
  Busca posibles coincidencias entre mascotas perdidas y encontradas.

  Funciones puras: no guardan estado ni lanzan excepciones.

  Si la especie es distinta el puntaje es 0 y la pareja se descarta. Si es la
  misma, se suman los criterios (⚠ pesos propuestos, el equipo puede
  ajustarlos en los atributos de este módulo):

  | Criterio | Puntos |
  |---|---|
  | Zona igual | 20 |
  | Color igual | 25 |
  | Tamaño igual / adyacente | 20 / 10 |
  | Nombre igual (ambos conocidos) | 15 |
  | Características | hasta 20, según el porcentaje de palabras en común |

  El máximo es 100. Los textos se comparan sin distinguir mayúsculas, tildes
  ni espacios alrededor (`"Negra "` coincide con `"negra"`).
  """

  alias Emergencias.Dominio.Mascota

  @puntos_zona 20
  @puntos_color 25
  @puntos_tamano 20
  @puntos_tamano_adyacente 10
  @puntos_nombre 15
  @puntos_caracteristicas 20

  @umbral_por_defecto 60

  # Palabras más cortas que esto ("y", "de", "la") no cuentan como palabras en común.
  @largo_minimo_palabra 3

  @orden_tamanos %{pequeno: 0, mediano: 1, grande: 2}

  @doc """
  Lista de criterios por defecto. Cada criterio es una función que recibe
  `(perdida, encontrada)` y devuelve sus puntos.
  """
  def criterios do
    [&zona/2, &color/2, &tamano/2, &nombre/2, &caracteristicas/2]
  end

  @doc """
  Puntaje de una pareja perdida–encontrada.

  Si la especie es distinta devuelve 0. Si no, recorre `criterios` de forma
  recursiva con un acumulador y suma los puntos de cada uno.
  """
  def puntaje(%Mascota{} = perdida, %Mascota{} = encontrada, criterios) when is_list(criterios) do
    if misma_especie?(perdida, encontrada),
      do: sumar_criterios(criterios, perdida, encontrada, 0),
      else: 0
  end

  # Recursiva de cola: el acumulador lleva la suma parcial.
  defp sumar_criterios([], _perdida, _encontrada, acumulado), do: acumulado

  defp sumar_criterios([criterio | resto], perdida, encontrada, acumulado) do
    sumar_criterios(resto, perdida, encontrada, acumulado + criterio.(perdida, encontrada))
  end

  @doc """
  Compara cada mascota perdida con cada encontrada y devuelve las parejas con
  puntaje ≥ `umbral` como `%{perdida_id: _, encontrada_id: _, puntaje: _}`,
  ordenadas de mayor a menor puntaje (los empates se ordenan por
  `perdida_id` y luego `encontrada_id`).

  Las parejas de especies distintas se descartan siempre, incluso con umbral 0.
  """
  def buscar(perdidas, encontradas, umbral \\ @umbral_por_defecto)
      when is_list(perdidas) and is_list(encontradas) and is_number(umbral) do
    criterios = criterios()

    for perdida <- perdidas,
        encontrada <- encontradas,
        misma_especie?(perdida, encontrada),
        puntos <- [puntaje(perdida, encontrada, criterios)],
        puntos >= umbral do
      %{perdida_id: perdida.id, encontrada_id: encontrada.id, puntaje: puntos}
    end
    |> Enum.sort_by(fn c -> {-c.puntaje, c.perdida_id, c.encontrada_id} end)
  end

  # ---------------------------------------------------------------------------
  # Criterios
  # ---------------------------------------------------------------------------

  @doc "#{@puntos_zona} puntos si la zona es la misma."
  def zona(perdida, encontrada), do: si_iguales(perdida.zona, encontrada.zona, @puntos_zona)

  @doc "#{@puntos_color} puntos si el color es el mismo."
  def color(perdida, encontrada), do: si_iguales(perdida.color, encontrada.color, @puntos_color)

  @doc """
  #{@puntos_tamano} puntos si el tamaño es igual, #{@puntos_tamano_adyacente} si
  es adyacente (pequeño–mediano o mediano–grande) y 0 en otro caso.
  """
  def tamano(perdida, encontrada) do
    case {Map.get(@orden_tamanos, perdida.tamano), Map.get(@orden_tamanos, encontrada.tamano)} do
      {nil, _} -> 0
      {_, nil} -> 0
      {igual, igual} -> @puntos_tamano
      {a, b} when abs(a - b) == 1 -> @puntos_tamano_adyacente
      _ -> 0
    end
  end

  @doc "#{@puntos_nombre} puntos si ambos reportes conocen el nombre y es el mismo."
  def nombre(%Mascota{nombre: nil}, _encontrada), do: 0
  def nombre(_perdida, %Mascota{nombre: nil}), do: 0

  def nombre(perdida, encontrada),
    do: si_iguales(perdida.nombre, encontrada.nombre, @puntos_nombre)

  @doc """
  Hasta #{@puntos_caracteristicas} puntos según el porcentaje de palabras en
  común: palabras compartidas / palabras distintas entre los dos textos
  (índice de Jaccard), redondeado a entero. Solo cuentan palabras de
  #{@largo_minimo_palabra} letras o más. Si alguno no tiene palabras, 0.
  """
  def caracteristicas(perdida, encontrada) do
    a = palabras(perdida.caracteristicas)
    b = palabras(encontrada.caracteristicas)

    case MapSet.size(MapSet.union(a, b)) do
      0 ->
        0

      total ->
        comunes = MapSet.size(MapSet.intersection(a, b))
        round(@puntos_caracteristicas * comunes / total)
    end
  end

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp misma_especie?(perdida, encontrada) do
    especie = normalizar(perdida.especie)
    especie != "" and especie == normalizar(encontrada.especie)
  end

  defp si_iguales(a, b, puntos) do
    texto = normalizar(a)
    if texto != "" and texto == normalizar(b), do: puntos, else: 0
  end

  defp palabras(texto) do
    texto
    |> normalizar()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(fn palabra -> String.length(palabra) >= @largo_minimo_palabra end)
    |> MapSet.new()
  end

  # Minúsculas, sin tildes y sin espacios alrededor. `nil` da "".
  defp normalizar(texto) when is_binary(texto) do
    minusculas = texto |> String.trim() |> String.downcase()

    case :unicode.characters_to_nfd_binary(minusculas) do
      descompuesto when is_binary(descompuesto) -> String.replace(descompuesto, ~r/\p{Mn}/u, "")
      _error -> minusculas
    end
  end

  defp normalizar(_otro), do: ""
end
