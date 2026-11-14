defmodule Emergencias.Procesos.RegistroActividadTest do
  # No es async: el proceso tiene un nombre global y escribe en un archivo fijo.
  use ExUnit.Case, async: false

  alias Emergencias.CSV
  alias Emergencias.Dominio.Actividad
  alias Emergencias.Procesos.RegistroActividad

  setup do
    File.rm(CSV.ruta(Actividad.archivo()))
    :ok
  end

  defp iniciar do
    {:ok, pid} = start_supervised(RegistroActividad)
    pid
  end

  defp filas_guardadas do
    {:ok, filas} = CSV.leer(CSV.ruta(Actividad.archivo()), &Actividad.de_linea/1)
    filas
  end

  describe "start_link/1" do
    test "inicia el proceso y lo registra con el nombre del módulo" do
      pid = iniciar()

      assert Process.whereis(RegistroActividad) == pid
      assert Process.alive?(pid)
    end

    test "si ya está iniciado devuelve :ya_iniciado" do
      iniciar()

      assert {:error, :ya_iniciado} = RegistroActividad.start_link([])
    end

    test "child_spec/1 permite ponerlo bajo un supervisor" do
      assert %{id: RegistroActividad, start: {RegistroActividad, :start_link, [[]]}} =
               RegistroActividad.child_spec([])
    end

    test "si actividad.csv tiene una línea corrupta devuelve el error" do
      :ok = File.mkdir_p(Path.dirname(CSV.ruta(Actividad.archivo())))

      :ok =
        File.write(CSV.ruta(Actividad.archivo()), Actividad.cabecera() <> "\nlinea corrupta\n")

      assert {:error, {:linea_invalida, 2}} = RegistroActividad.start_link([])
      assert Process.whereis(RegistroActividad) == nil
    end
  end

  describe "registrar/3 y listar/1" do
    test "registra 3 actividades de 2 usuarios y listar filtra por usuario" do
      iniciar()

      assert :ok = RegistroActividad.registrar("laura", "crear_necesidad", :ok)
      assert :ok = RegistroActividad.registrar("pedro", "asignar", {:error, :sin_stock})
      assert :ok = RegistroActividad.registrar("laura", "listar", "ok")

      assert {:ok, todas} = RegistroActividad.listar(:todos)
      assert Enum.map(todas, & &1.comando) == ["crear_necesidad", "asignar", "listar"]

      assert {:ok, de_laura} = RegistroActividad.listar("laura")
      assert Enum.map(de_laura, & &1.comando) == ["crear_necesidad", "listar"]
      assert Enum.all?(de_laura, fn actividad -> actividad.usuario == "laura" end)

      assert {:ok, [de_pedro]} = RegistroActividad.listar("pedro")
      assert de_pedro.resultado == "error:sin_stock"

      assert {:ok, []} = RegistroActividad.listar("nadie")
    end

    test "el archivo actividad.csv tiene 3 filas" do
      iniciar()

      :ok = RegistroActividad.registrar("laura", "crear_necesidad", :ok)
      :ok = RegistroActividad.registrar("pedro", "asignar", {:error, :sin_stock})
      :ok = RegistroActividad.registrar("laura", "listar", :ok)

      # Los mensajes de un mismo remitente llegan en orden: cuando listar/1
      # responde, el proceso ya procesó (y guardó) los tres registrar/3.
      assert {:ok, _lista} = RegistroActividad.listar(:todos)

      assert [primera, segunda, tercera] = filas_guardadas()
      assert {primera.usuario, segunda.usuario, tercera.usuario} == {"laura", "pedro", "laura"}
    end

    test "al reiniciar carga las actividades guardadas" do
      iniciar()
      :ok = RegistroActividad.registrar("laura", "crear_necesidad", :ok)
      :ok = RegistroActividad.registrar("pedro", "asignar", :ok)
      assert {:ok, [_, _]} = RegistroActividad.listar(:todos)

      :ok = stop_supervised(RegistroActividad)
      iniciar()

      assert {:ok, [_, _] = lista} = RegistroActividad.listar(:todos)
      assert Enum.map(lista, & &1.usuario) == ["laura", "pedro"]
    end

    test "registrar rechaza datos inválidos y no guarda nada" do
      iniciar()

      assert {:error, :texto_vacio} = RegistroActividad.registrar("", "listar", :ok)
      assert {:error, :texto_vacio} = RegistroActividad.registrar("laura", "", :ok)
      assert {:error, :resultado_invalido} = RegistroActividad.registrar("laura", "x", "mal")

      assert {:ok, []} = RegistroActividad.listar(:todos)
      assert filas_guardadas() == []
    end

    test "listar rechaza un usuario que no es texto ni :todos" do
      iniciar()

      assert {:error, :usuario_invalido} = RegistroActividad.listar(nil)
      assert {:error, :usuario_invalido} = RegistroActividad.listar(:otro)
    end
  end

  describe "mensajes desconocidos" do
    test "un mensaje desconocido no mata el proceso ni se acumula en el buzón" do
      pid = iniciar()

      send(pid, :basura)
      send(pid, {:algo, "raro", 1})
      send(pid, {:registrar, "no es una actividad"})
      send(pid, {:listar, :no_es_pid, :todos})

      :ok = RegistroActividad.registrar("laura", "listar", :ok)

      assert Process.alive?(pid)
      assert {:ok, [%Actividad{usuario: "laura"}]} = RegistroActividad.listar(:todos)
      assert {:message_queue_len, 0} = Process.info(pid, :message_queue_len)
    end
  end

  describe "sin iniciar" do
    test "registrar y listar devuelven :no_iniciado" do
      assert Process.whereis(RegistroActividad) == nil

      assert {:error, :no_iniciado} = RegistroActividad.registrar("laura", "listar", :ok)
      assert {:error, :no_iniciado} = RegistroActividad.listar(:todos)
    end
  end
end
