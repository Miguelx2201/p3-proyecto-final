defmodule Emergencias.Servicios.Ordenamiento do
  @moduledoc """
  Ordenamiento propio y recursivo (sin `Enum.sort`), por inserción.

  Funciona con cualquier lista y cualquier criterio: el criterio es una función
  `antes?.(a, b)` que devuelve `true` si `a` debe ir antes que `b`.

  El orden es estable: si `antes?` devuelve `false` en ambos sentidos (empate),
  los elementos conservan el orden que tenían en la lista original.
  """

  @doc """
  Ordena `lista` según `antes?`.

  ## Ejemplos

      iex> Emergencias.Servicios.Ordenamiento.ordenar([3, 1, 2], &(&1 < &2))
      [1, 2, 3]

      iex> Emergencias.Servicios.Ordenamiento.ordenar([3, 1, 2], &(&1 > &2))
      [3, 2, 1]

      iex> Emergencias.Servicios.Ordenamiento.ordenar([], &(&1 < &2))
      []
  """
  @spec ordenar([elem], (elem, elem -> boolean())) :: [elem] when elem: term()
  def ordenar(lista, antes?), do: ordenar(lista, antes?, [])

  # Toma los elementos uno a uno y los inserta en `ordenada`, que siempre
  # está ordenada.
  defp ordenar([], _antes?, ordenada), do: ordenada

  defp ordenar([x | resto], antes?, ordenada),
    do: ordenar(resto, antes?, insertar(x, ordenada, antes?))

  # Inserta `x` antes del primer elemento al que debe preceder. En un empate
  # `antes?` es falso, así que `x` queda después de los iguales (estabilidad).
  defp insertar(x, [], _antes?), do: [x]

  defp insertar(x, [y | resto] = lista, antes?) do
    if antes?.(x, y), do: [x | lista], else: [y | insertar(x, resto, antes?)]
  end
end
