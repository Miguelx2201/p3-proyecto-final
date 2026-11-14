defmodule Emergencias.Servicios.OrdenamientoTest do
  use ExUnit.Case, async: true

  alias Emergencias.Servicios.Ordenamiento

  doctest Emergencias.Servicios.Ordenamiento

  defp menor(a, b), do: a < b
  defp mayor(a, b), do: a > b

  describe "ordenar/2" do
    test "lista vacía devuelve lista vacía" do
      assert Ordenamiento.ordenar([], &menor/2) == []
    end

    test "un elemento devuelve la misma lista" do
      assert Ordenamiento.ordenar([7], &menor/2) == [7]
    end

    test "ordena una lista desordenada de menor a mayor" do
      assert Ordenamiento.ordenar([5, 2, 9, 1, 7], &menor/2) == [1, 2, 5, 7, 9]
    end

    test "con el criterio contrario ordena de mayor a menor" do
      assert Ordenamiento.ordenar([5, 2, 9, 1, 7], &mayor/2) == [9, 7, 5, 2, 1]
    end

    test "una lista ya ordenada no cambia" do
      assert Ordenamiento.ordenar([1, 2, 3, 4], &menor/2) == [1, 2, 3, 4]
    end

    test "una lista en orden inverso queda ordenada" do
      assert Ordenamiento.ordenar([4, 3, 2, 1], &menor/2) == [1, 2, 3, 4]
    end

    test "conserva los elementos repetidos" do
      assert Ordenamiento.ordenar([3, 1, 3, 2, 1], &menor/2) == [1, 1, 2, 3, 3]
    end

    test "es estable: en un empate conserva el orden original" do
      lista = [{2, :a}, {1, :b}, {2, :c}, {1, :d}, {2, :e}]
      antes? = fn {x, _}, {y, _} -> x < y end

      assert Ordenamiento.ordenar(lista, antes?) ==
               [{1, :b}, {1, :d}, {2, :a}, {2, :c}, {2, :e}]
    end

    test "sirve para cualquier tipo de dato" do
      assert Ordenamiento.ordenar(["pera", "manzana", "kiwi"], &menor/2) ==
               ["kiwi", "manzana", "pera"]
    end

    test "coincide con Enum.sort en varias listas" do
      listas = [
        [],
        [1],
        [2, 1],
        [1, 2],
        [9, 8, 7, 6, 5, 4, 3, 2, 1],
        [4, 4, 4],
        [3, -1, 0, 3, 10, -7, 2, 2],
        Enum.map(1..50, fn n -> rem(n * 37, 23) end)
      ]

      for lista <- listas do
        assert Ordenamiento.ordenar(lista, &menor/2) == Enum.sort(lista)
      end
    end

    test "no modifica la lista original (datos inmutables)" do
      original = [3, 1, 2]
      _ = Ordenamiento.ordenar(original, &menor/2)
      assert original == [3, 1, 2]
    end
  end
end
