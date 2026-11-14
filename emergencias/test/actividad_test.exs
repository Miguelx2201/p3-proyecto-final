defmodule Emergencias.Dominio.ActividadTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Actividad
  alias Emergencias.Fabrica

  describe "nuevo/3" do
    test "crea una actividad válida con la fecha actual" do
      assert {:ok, %Actividad{} = actividad} = Actividad.nuevo("laura", "crear_necesidad", :ok)
      assert actividad.usuario == "laura"
      assert actividad.comando == "crear_necesidad"
      assert actividad.resultado == "ok"
      assert {:ok, _fecha, _desfase} = DateTime.from_iso8601(actividad.fecha)
    end

    test "acepta {:ok, valor} y lo guarda como ok" do
      assert {:ok, %Actividad{resultado: "ok"}} = Actividad.nuevo("laura", "listar", {:ok, [1]})
    end

    test "convierte {:error, razon} en error:razon" do
      assert {:ok, %Actividad{resultado: "error:sin_stock"}} =
               Actividad.nuevo("laura", "asignar", {:error, :sin_stock})
    end

    test "acepta el resultado ya como texto" do
      assert {:ok, %Actividad{resultado: "ok"}} = Actividad.nuevo("laura", "listar", "ok")

      assert {:ok, %Actividad{resultado: "error:no_encontrado"}} =
               Actividad.nuevo("laura", "ver", "error:no_encontrado")
    end

    test "rechaza un usuario vacío o que no es texto" do
      assert {:error, :texto_vacio} = Actividad.nuevo("", "listar", :ok)
      assert {:error, :texto_vacio} = Actividad.nuevo("   ", "listar", :ok)
      assert {:error, :texto_vacio} = Actividad.nuevo(nil, "listar", :ok)
    end

    test "rechaza un comando vacío o que no es texto" do
      assert {:error, :texto_vacio} = Actividad.nuevo("laura", "", :ok)
      assert {:error, :texto_vacio} = Actividad.nuevo("laura", nil, :ok)
    end

    test "rechaza un resultado inválido" do
      assert {:error, :resultado_invalido} = Actividad.nuevo("laura", "listar", "bien")
      assert {:error, :resultado_invalido} = Actividad.nuevo("laura", "listar", "error:")
      assert {:error, :resultado_invalido} = Actividad.nuevo("laura", "listar", "error")
      assert {:error, :resultado_invalido} = Actividad.nuevo("laura", "listar", {:error, "texto"})
      assert {:error, :resultado_invalido} = Actividad.nuevo("laura", "listar", 42)
    end
  end

  describe "to_linea/1 y de_linea/1" do
    test "ida y vuelta conserva la actividad" do
      actividad = Fabrica.actividad(resultado: "error:sin_cupo")

      assert Actividad.to_linea(actividad) ==
               "2026-01-01T00:00:00Z;laura;crear_necesidad;error:sin_cupo"

      assert {:ok, ^actividad} = actividad |> Actividad.to_linea() |> Actividad.de_linea()
    end

    test "to_linea sanitiza el punto y coma de los textos libres" do
      linea = Fabrica.actividad(comando: "crear;necesidad") |> Actividad.to_linea()

      assert {:ok, %Actividad{comando: "crear necesidad"}} = Actividad.de_linea(linea)
    end

    test "de_linea rechaza una cantidad de campos incorrecta" do
      assert {:error, :linea_invalida} = Actividad.de_linea("solo;tres;campos")
      assert {:error, :linea_invalida} = Actividad.de_linea("a;b;c;d;e")
      assert {:error, :linea_invalida} = Actividad.de_linea("")
    end

    test "de_linea rechaza una línea que no es texto" do
      assert {:error, :linea_invalida} = Actividad.de_linea(nil)
    end

    test "de_linea rechaza una fecha inválida" do
      assert {:error, :fecha_invalida} = Actividad.de_linea("ayer;laura;listar;ok")
    end

    test "de_linea rechaza usuario o comando vacíos" do
      assert {:error, :texto_vacio} = Actividad.de_linea("2026-01-01T00:00:00Z;;listar;ok")
      assert {:error, :texto_vacio} = Actividad.de_linea("2026-01-01T00:00:00Z;laura;;ok")
    end

    test "de_linea rechaza un resultado inválido" do
      assert {:error, :resultado_invalido} =
               Actividad.de_linea("2026-01-01T00:00:00Z;laura;listar;quizas")
    end
  end

  test "la fábrica construye una actividad válida y acepta cambios" do
    assert %Actividad{usuario: "laura", resultado: "ok"} = Fabrica.actividad()
    assert %Actividad{usuario: "pedro"} = Fabrica.actividad(usuario: "pedro")
  end
end
