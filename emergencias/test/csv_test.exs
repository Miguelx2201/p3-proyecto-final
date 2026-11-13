defmodule Emergencias.CSVTest do
  # async: false porque algunas pruebas cambian la configuración global :data_dir
  use ExUnit.Case, async: false

  alias Emergencias.CSV
  alias Emergencias.Util

  doctest Emergencias.CSV

  @moduletag :tmp_dir
  @cabecera "nombre;cantidad"

  defp a_linea({nombre, cantidad}), do: CSV.unir([nombre, cantidad])

  defp de_linea(linea) do
    with [nombre, texto] <- CSV.separar(linea),
         {:ok, cantidad} <- Util.parsear_entero(texto) do
      {:ok, {nombre, cantidad}}
    else
      _ -> {:error, :linea_invalida}
    end
  end

  describe "ruta/1" do
    setup do
      original = Application.get_env(:emergencias, :data_dir)

      on_exit(fn ->
        if original,
          do: Application.put_env(:emergencias, :data_dir, original),
          else: Application.delete_env(:emergencias, :data_dir)
      end)
    end

    test "usa data por defecto" do
      Application.delete_env(:emergencias, :data_dir)
      assert CSV.ruta("usuarios.csv") == Path.join("data", "usuarios.csv")
    end

    test "usa la carpeta configurada" do
      Application.put_env(:emergencias, :data_dir, "otra_carpeta")
      assert CSV.ruta("usuarios.csv") == Path.join("otra_carpeta", "usuarios.csv")
    end
  end

  describe "escribir/4 y leer/2" do
    test "ida y vuelta devuelve los mismos datos y en el mismo orden", %{tmp_dir: dir} do
      ruta = Path.join(dir, "datos.csv")
      datos = [{"agua", 50}, {"alimentos", 10}, {"rescate", 0}]

      assert :ok = CSV.escribir(ruta, @cabecera, datos, &a_linea/1)
      assert {:ok, ^datos} = CSV.leer(ruta, &de_linea/1)
    end

    test "el archivo tiene cabecera y una línea por entidad", %{tmp_dir: dir} do
      ruta = Path.join(dir, "datos.csv")
      :ok = CSV.escribir(ruta, @cabecera, [{"agua", 50}, {"pan", 3}], &a_linea/1)

      assert File.read!(ruta) == "nombre;cantidad\nagua;50\npan;3\n"
    end

    test "crea la carpeta si no existe", %{tmp_dir: dir} do
      ruta = Path.join([dir, "nueva", "subcarpeta", "datos.csv"])
      assert :ok = CSV.escribir(ruta, @cabecera, [{"agua", 1}], &a_linea/1)
      assert {:ok, [{"agua", 1}]} = CSV.leer(ruta, &de_linea/1)
    end

    test "sobrescribe el contenido anterior y no deja archivo temporal", %{tmp_dir: dir} do
      ruta = Path.join(dir, "datos.csv")
      :ok = CSV.escribir(ruta, @cabecera, [{"a", 1}, {"b", 2}], &a_linea/1)
      :ok = CSV.escribir(ruta, @cabecera, [{"c", 3}], &a_linea/1)

      assert {:ok, [{"c", 3}]} = CSV.leer(ruta, &de_linea/1)
      refute File.exists?(ruta <> ".tmp")
    end

    test "una lista vacía deja solo la cabecera y se lee como lista vacía", %{tmp_dir: dir} do
      ruta = Path.join(dir, "vacio.csv")
      assert :ok = CSV.escribir(ruta, @cabecera, [], &a_linea/1)
      assert File.read!(ruta) == "nombre;cantidad\n"
      assert {:ok, []} = CSV.leer(ruta, &de_linea/1)
    end

    test "devuelve error (sin excepción) si no se puede escribir", %{tmp_dir: dir} do
      bloqueo = Path.join(dir, "archivo")
      File.write!(bloqueo, "x")
      ruta = Path.join([bloqueo, "sub", "datos.csv"])

      assert {:error, _razon} = CSV.escribir(ruta, @cabecera, [{"a", 1}], &a_linea/1)
    end
  end

  describe "leer/2" do
    test "archivo inexistente devuelve {:ok, []}", %{tmp_dir: dir} do
      assert {:ok, []} = CSV.leer(Path.join(dir, "no_existe.csv"), &de_linea/1)
    end

    test "archivo completamente vacío devuelve {:ok, []}", %{tmp_dir: dir} do
      ruta = Path.join(dir, "vacio.csv")
      File.write!(ruta, "")
      assert {:ok, []} = CSV.leer(ruta, &de_linea/1)
    end

    test "una línea corrupta devuelve error con su número de línea", %{tmp_dir: dir} do
      ruta = Path.join(dir, "corrupto.csv")
      File.write!(ruta, "nombre;cantidad\nagua;50\nagua;abc\npan;3\n")

      assert {:error, {:linea_invalida, 3}} = CSV.leer(ruta, &de_linea/1)
    end

    test "líneas con muy pocos o demasiados campos son inválidas", %{tmp_dir: dir} do
      ruta = Path.join(dir, "campos.csv")
      File.write!(ruta, "nombre;cantidad\nsolo_uno\n")
      assert {:error, {:linea_invalida, 2}} = CSV.leer(ruta, &de_linea/1)

      File.write!(ruta, "nombre;cantidad\na;1;2\n")
      assert {:error, {:linea_invalida, 2}} = CSV.leer(ruta, &de_linea/1)
    end

    test "acepta saltos de línea de Windows y líneas vacías", %{tmp_dir: dir} do
      ruta = Path.join(dir, "windows.csv")
      File.write!(ruta, "nombre;cantidad\r\nagua;50\r\n\r\npan;3\r\n")

      assert {:ok, [{"agua", 50}, {"pan", 3}]} = CSV.leer(ruta, &de_linea/1)
    end

    test "funciona aunque el archivo no termine en salto de línea", %{tmp_dir: dir} do
      ruta = Path.join(dir, "sin_final.csv")
      File.write!(ruta, "nombre;cantidad\nagua;50")

      assert {:ok, [{"agua", 50}]} = CSV.leer(ruta, &de_linea/1)
    end

    test "leer una carpeta devuelve error sin excepción", %{tmp_dir: dir} do
      assert {:error, _razon} = CSV.leer(dir, &de_linea/1)
    end

    test "maneja muchas líneas sin problemas", %{tmp_dir: dir} do
      ruta = Path.join(dir, "grande.csv")
      datos = for n <- 1..50_000, do: {"item", n}

      :ok = CSV.escribir(ruta, @cabecera, datos, &a_linea/1)
      assert {:ok, leidos} = CSV.leer(ruta, &de_linea/1)
      assert length(leidos) == 50_000
      assert List.last(leidos) == {"item", 50_000}
    end
  end

  describe "agregar/4" do
    test "crea el archivo con cabecera si no existe", %{tmp_dir: dir} do
      ruta = Path.join([dir, "historial", "h.csv"])

      assert :ok = CSV.agregar(ruta, @cabecera, {"agua", 5}, &a_linea/1)
      assert File.read!(ruta) == "nombre;cantidad\nagua;5\n"
    end

    test "agrega al final sin borrar lo anterior", %{tmp_dir: dir} do
      ruta = Path.join(dir, "h.csv")

      :ok = CSV.agregar(ruta, @cabecera, {"a", 1}, &a_linea/1)
      :ok = CSV.agregar(ruta, @cabecera, {"b", 2}, &a_linea/1)
      :ok = CSV.agregar(ruta, @cabecera, {"c", 3}, &a_linea/1)

      assert {:ok, [{"a", 1}, {"b", 2}, {"c", 3}]} = CSV.leer(ruta, &de_linea/1)
    end

    test "agrega a un archivo escrito antes con escribir/4", %{tmp_dir: dir} do
      ruta = Path.join(dir, "h.csv")
      :ok = CSV.escribir(ruta, @cabecera, [{"a", 1}], &a_linea/1)
      :ok = CSV.agregar(ruta, @cabecera, {"b", 2}, &a_linea/1)

      assert {:ok, [{"a", 1}, {"b", 2}]} = CSV.leer(ruta, &de_linea/1)
    end

    test "devuelve error (sin excepción) si no se puede escribir", %{tmp_dir: dir} do
      bloqueo = Path.join(dir, "archivo")
      File.write!(bloqueo, "x")

      assert {:error, _razon} =
               CSV.agregar(Path.join([bloqueo, "h.csv"]), @cabecera, {"a", 1}, &a_linea/1)
    end
  end

  describe "separar/1 y unir/1" do
    test "son inversas para campos sin ;" do
      campos = ["R001", "agua", "50", ""]
      assert campos == campos |> CSV.unir() |> CSV.separar()
    end

    test "unir convierte números y átomos a texto" do
      assert CSV.unir(["a", 5, :critica, nil]) == "a;5;critica;"
    end
  end
end
