defmodule Emergencias.Dominio.CoincidenciaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Coincidencia
  alias Emergencias.Fabrica

  # La fábrica crea por defecto: perro, Luna, negra, mediano, centro, sin características.
  defp perdida(atributos \\ []), do: Fabrica.mascota(Keyword.merge([tipo: :perdida], atributos))

  defp encontrada(atributos \\ []),
    do: Fabrica.mascota(Keyword.merge([id: "M101", tipo: :encontrada], atributos))

  describe "puntaje/3" do
    test "coincidencia casi perfecta" do
      p = perdida(caracteristicas: "collar rojo, mancha blanca en el pecho")
      e = encontrada(caracteristicas: "Collar rojo y mancha blanca")

      # zona 20 + color 25 + tamaño 20 + nombre 15 + características round(20 * 4/5) = 16
      assert Coincidencia.puntaje(p, e, Coincidencia.criterios()) == 96
    end

    test "coincidencia perfecta suma 100" do
      p = perdida(caracteristicas: "collar rojo")
      e = encontrada(caracteristicas: "collar rojo")
      assert Coincidencia.puntaje(p, e, Coincidencia.criterios()) == 100
    end

    test "especies distintas dan 0 aunque todo lo demás coincida" do
      p = perdida(caracteristicas: "collar rojo")
      e = encontrada(especie: "gato", caracteristicas: "collar rojo")
      assert Coincidencia.puntaje(p, e, Coincidencia.criterios()) == 0
    end

    test "la especie se compara sin mayúsculas ni espacios" do
      p = perdida(especie: "Perro ")
      e = encontrada(especie: "perro")
      assert Coincidencia.puntaje(p, e, Coincidencia.criterios()) > 0
    end

    test "recorre solo los criterios recibidos" do
      p = perdida()
      e = encontrada()

      assert Coincidencia.puntaje(p, e, []) == 0
      assert Coincidencia.puntaje(p, e, [&Coincidencia.zona/2]) == 20
      assert Coincidencia.puntaje(p, e, [&Coincidencia.zona/2, &Coincidencia.color/2]) == 45
    end

    test "acepta criterios propios (funciones de dos argumentos)" do
      siempre_cinco = fn _perdida, _encontrada -> 5 end
      assert Coincidencia.puntaje(perdida(), encontrada(), [siempre_cinco, siempre_cinco]) == 10
    end
  end

  describe "criterios" do
    test "zona: 20 si es igual, 0 si no" do
      assert Coincidencia.zona(perdida(), encontrada()) == 20
      assert Coincidencia.zona(perdida(), encontrada(zona: "norte")) == 0
    end

    test "color: 25 si es igual (sin mayúsculas ni tildes), 0 si no" do
      assert Coincidencia.color(perdida(color: "Marrón"), encontrada(color: "marron ")) == 25
      assert Coincidencia.color(perdida(), encontrada(color: "blanca")) == 0
    end

    test "tamaño: 20 igual, 10 adyacente, 0 opuesto" do
      assert Coincidencia.tamano(perdida(tamano: :mediano), encontrada(tamano: :mediano)) == 20
      assert Coincidencia.tamano(perdida(tamano: :pequeno), encontrada(tamano: :mediano)) == 10
      assert Coincidencia.tamano(perdida(tamano: :grande), encontrada(tamano: :mediano)) == 10
      assert Coincidencia.tamano(perdida(tamano: :pequeno), encontrada(tamano: :grande)) == 0
    end

    test "nombre: 15 solo si ambos lo conocen y es el mismo" do
      assert Coincidencia.nombre(perdida(nombre: "Luna"), encontrada(nombre: "luna")) == 15
      assert Coincidencia.nombre(perdida(nombre: "Luna"), encontrada(nombre: "Toby")) == 0
      assert Coincidencia.nombre(perdida(nombre: "Luna"), encontrada(nombre: nil)) == 0
      assert Coincidencia.nombre(perdida(nombre: nil), encontrada(nombre: nil)) == 0
    end

    test "características: proporcional a las palabras en común" do
      p = perdida(caracteristicas: "collar rojo")

      assert Coincidencia.caracteristicas(p, encontrada(caracteristicas: "collar rojo")) == 20
      # {collar} / {collar, rojo, azul} = 1/3 → round(6.67) = 7
      assert Coincidencia.caracteristicas(p, encontrada(caracteristicas: "collar azul")) == 7
      assert Coincidencia.caracteristicas(p, encontrada(caracteristicas: "cola corta")) == 0
    end

    test "características: ignora palabras cortas y vacíos" do
      p = perdida(caracteristicas: "y de la")
      e = encontrada(caracteristicas: "y de la")
      assert Coincidencia.caracteristicas(p, e) == 0
      assert Coincidencia.caracteristicas(perdida(), encontrada()) == 0
    end
  end

  describe "buscar/3" do
    test "devuelve la coincidencia casi perfecta con su puntaje" do
      p = perdida(caracteristicas: "collar rojo, mancha blanca en el pecho")
      e = encontrada(caracteristicas: "collar rojo y mancha blanca")

      assert Coincidencia.buscar([p], [e]) == [
               %{perdida_id: "M001", encontrada_id: "M101", puntaje: 96}
             ]
    end

    test "descarta especies distintas, incluso con umbral 0" do
      p = perdida()
      e = encontrada(especie: "gato")

      assert Coincidencia.buscar([p], [e]) == []
      assert Coincidencia.buscar([p], [e], 0) == []
    end

    test "caso bajo el umbral: no se incluye" do
      p = perdida(nombre: nil)
      # zona 20 + tamaño adyacente 10 = 30
      e = encontrada(nombre: nil, color: "blanca", tamano: :grande)

      assert Coincidencia.puntaje(p, e, Coincidencia.criterios()) == 30
      assert Coincidencia.buscar([p], [e]) == []
      assert [%{puntaje: 30}] = Coincidencia.buscar([p], [e], 30)
    end

    test "el umbral por defecto es 60 e incluye el puntaje igual al umbral" do
      p = perdida(nombre: nil)
      # zona 20 + color 25 + tamaño 20 = 65
      e = encontrada(nombre: nil)

      assert [%{puntaje: 65}] = Coincidencia.buscar([p], [e])
      assert [%{puntaje: 65}] = Coincidencia.buscar([p], [e], 65)
      assert [] = Coincidencia.buscar([p], [e], 66)
    end

    test "ordena el resultado de mayor a menor puntaje" do
      p = perdida(caracteristicas: "collar rojo")

      sin_datos = encontrada(id: "M101", nombre: nil)
      con_collar = encontrada(id: "M102", nombre: nil, caracteristicas: "collar")
      identica = encontrada(id: "M103", caracteristicas: "collar rojo")

      assert Coincidencia.buscar([p], [sin_datos, con_collar, identica]) == [
               %{perdida_id: "M001", encontrada_id: "M103", puntaje: 100},
               %{perdida_id: "M001", encontrada_id: "M102", puntaje: 75},
               %{perdida_id: "M001", encontrada_id: "M101", puntaje: 65}
             ]
    end

    test "en un empate ordena por perdida_id y luego encontrada_id" do
      p2 = perdida(id: "M002")
      p1 = perdida(id: "M001")
      e = encontrada()

      assert [%{perdida_id: "M001"}, %{perdida_id: "M002"}] = Coincidencia.buscar([p2, p1], [e])
    end

    test "compara todas las perdidas contra todas las encontradas" do
      perro = perdida(id: "M001")
      gato = perdida(id: "M002", especie: "gato", nombre: "Michi")
      perro_encontrado = encontrada(id: "M101")
      gato_encontrado = encontrada(id: "M102", especie: "gato", nombre: "Michi")

      resultado = Coincidencia.buscar([perro, gato], [perro_encontrado, gato_encontrado])

      assert Enum.map(resultado, &{&1.perdida_id, &1.encontrada_id}) |> Enum.sort() == [
               {"M001", "M101"},
               {"M002", "M102"}
             ]
    end

    test "listas vacías dan una lista vacía" do
      assert Coincidencia.buscar([], [encontrada()]) == []
      assert Coincidencia.buscar([perdida()], []) == []
    end
  end
end
