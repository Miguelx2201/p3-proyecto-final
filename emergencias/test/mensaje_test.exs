defmodule Emergencias.Dominio.MensajeTest do
  use ExUnit.Case, async: true

  alias Emergencias.CSV
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Fabrica

  doctest Mensaje

  defp crear_valido(atributos \\ []) do
    datos =
      Keyword.merge(
        [id: "MS001", remitente: "laura", documento: "1094", contenido: "Estamos bien"],
        atributos
      )

    Mensaje.crear(datos[:id], datos[:remitente], datos[:documento], datos[:contenido])
  end

  describe "estados/0" do
    test "devuelve los estados permitidos" do
      assert Mensaje.estados() == [:pendiente, :entregado]
    end
  end

  describe "crear/4" do
    test "crea el mensaje pendiente con la fecha actual" do
      assert {:ok, mensaje} = crear_valido()

      assert %Mensaje{
               id: "MS001",
               remitente: "laura",
               documento_destinatario: "1094",
               contenido: "Estamos bien",
               estado: :pendiente
             } = mensaje

      assert {:ok, _fecha, 0} = DateTime.from_iso8601(mensaje.fecha)
    end

    test "sanitiza el contenido con Util.sanitizar_texto/1" do
      assert {:ok, mensaje} = crear_valido(contenido: "  Estamos bien;\nte buscamos  ")
      assert mensaje.contenido == "Estamos bien  te buscamos"
    end

    test "quita espacios de los extremos de id, remitente y documento" do
      assert {:ok, mensaje} =
               crear_valido(id: " MS001 ", remitente: " laura ", documento: " 1094 ")

      assert {mensaje.id, mensaje.remitente, mensaje.documento_destinatario} ==
               {"MS001", "laura", "1094"}
    end

    test "rechaza contenido vacío, solo espacios, que quede vacío al sanitizar o que no sea texto" do
      assert {:error, :contenido_vacio} = crear_valido(contenido: "")
      assert {:error, :contenido_vacio} = crear_valido(contenido: "   ")
      assert {:error, :contenido_vacio} = crear_valido(contenido: " ; \n ")
      assert {:error, :contenido_vacio} = crear_valido(contenido: nil)
      assert {:error, :contenido_vacio} = crear_valido(contenido: 123)
    end

    test "rechaza id vacío" do
      assert {:error, :id_vacio} = crear_valido(id: "")
      assert {:error, :id_vacio} = crear_valido(id: nil)
    end

    test "rechaza remitente vacío" do
      assert {:error, :remitente_vacio} = crear_valido(remitente: "  ")
      assert {:error, :remitente_vacio} = crear_valido(remitente: nil)
    end

    test "rechaza documento del destinatario vacío" do
      assert {:error, :documento_vacio} = crear_valido(documento: "")
      assert {:error, :documento_vacio} = crear_valido(documento: 1094)
    end
  end

  describe "marcar_entregado/1" do
    test "pasa un mensaje pendiente a entregado sin tocar los demás campos" do
      mensaje = Fabrica.mensaje()

      assert {:ok, entregado} = Mensaje.marcar_entregado(mensaje)
      assert entregado == %{mensaje | estado: :entregado}
    end

    test "marcar entregado dos veces devuelve :ya_entregado" do
      {:ok, mensaje} = crear_valido()
      {:ok, entregado} = Mensaje.marcar_entregado(mensaje)

      assert {:error, :ya_entregado} = Mensaje.marcar_entregado(entregado)
    end

    test "no modifica el mensaje original" do
      mensaje = Fabrica.mensaje()
      {:ok, _entregado} = Mensaje.marcar_entregado(mensaje)

      assert mensaje.estado == :pendiente
    end

    test "rechaza algo que no es un mensaje" do
      assert {:error, :mensaje_invalido} = Mensaje.marcar_entregado(%{estado: :pendiente})
      assert {:error, :mensaje_invalido} = Mensaje.marcar_entregado(nil)
    end
  end

  describe "para_destinatario/2" do
    setup do
      mensajes = [
        Fabrica.mensaje(id: "MS001", documento_destinatario: "1094"),
        Fabrica.mensaje(id: "MS002", documento_destinatario: "2020"),
        Fabrica.mensaje(id: "MS003", documento_destinatario: "1094", estado: :entregado),
        Fabrica.mensaje(id: "MS004", documento_destinatario: "10945")
      ]

      %{mensajes: mensajes}
    end

    defp ids(mensajes), do: Enum.map(mensajes, & &1.id)

    test "devuelve solo los mensajes de esa persona, en el mismo orden", %{mensajes: mensajes} do
      assert ids(Mensaje.para_destinatario(mensajes, "1094")) == ["MS001", "MS003"]
      assert ids(Mensaje.para_destinatario(mensajes, "2020")) == ["MS002"]
    end

    test "compara el documento exacto, con trim del buscado", %{mensajes: mensajes} do
      assert ids(Mensaje.para_destinatario(mensajes, " 1094 ")) == ["MS001", "MS003"]
      assert Mensaje.para_destinatario(mensajes, "109") == []
    end

    test "sin mensajes para esa persona devuelve []", %{mensajes: mensajes} do
      assert Mensaje.para_destinatario(mensajes, "9999") == []
      assert Mensaje.para_destinatario([], "1094") == []
    end

    test "ignora elementos que no son mensajes y entradas inválidas", %{mensajes: mensajes} do
      assert ids(
               Mensaje.para_destinatario([%{documento_destinatario: "1094"} | mensajes], "1094")
             ) ==
               ["MS001", "MS003"]

      assert Mensaje.para_destinatario(mensajes, nil) == []
      assert Mensaje.para_destinatario(:no_es_lista, "1094") == []
    end
  end

  describe "CSV de mensajes" do
    test "nombre del archivo y cabecera" do
      assert Mensaje.archivo_csv() == "mensajes.csv"
      assert Mensaje.cabecera_csv() == "id;fecha;remitente;documento;contenido;estado"
    end

    test "convierte a línea y de vuelta a mensaje" do
      mensaje = Fabrica.mensaje()
      linea = Mensaje.to_linea(mensaje)

      assert linea ==
               "MS001;2026-01-01T00:00:00Z;laura;1094;Estamos bien, te esperamos en el albergue;pendiente"

      assert {:ok, ^mensaje} = Mensaje.de_linea(linea)

      {:ok, entregado} = Mensaje.marcar_entregado(mensaje)
      assert {:ok, ^entregado} = Mensaje.de_linea(Mensaje.to_linea(entregado))
    end

    test "sanitiza el contenido al escribir la línea" do
      mensaje = Fabrica.mensaje(contenido: "hola;\nmamá")

      assert Mensaje.to_linea(mensaje) ==
               "MS001;2026-01-01T00:00:00Z;laura;1094;hola  mamá;pendiente"
    end

    test "rechaza líneas corruptas" do
      fecha = "2026-01-01T00:00:00Z"

      assert {:error, :linea_invalida} = Mensaje.de_linea("MS001;#{fecha};laura;1094;hola")

      assert {:error, :linea_invalida} =
               Mensaje.de_linea("MS001;#{fecha};laura;1094;hola;pendiente;x")

      assert {:error, :linea_invalida} = Mensaje.de_linea(nil)
      assert {:error, :id_vacio} = Mensaje.de_linea(";#{fecha};laura;1094;hola;pendiente")
      assert {:error, :fecha_vacia} = Mensaje.de_linea("MS001;;laura;1094;hola;pendiente")
      assert {:error, :remitente_vacio} = Mensaje.de_linea("MS001;#{fecha};;1094;hola;pendiente")
      assert {:error, :documento_vacio} = Mensaje.de_linea("MS001;#{fecha};laura;;hola;pendiente")

      assert {:error, :contenido_vacio} =
               Mensaje.de_linea("MS001;#{fecha};laura;1094; ;pendiente")

      assert {:error, :estado_invalido} = Mensaje.de_linea("MS001;#{fecha};laura;1094;hola;leido")
    end

    @tag :tmp_dir
    test "ida y vuelta por archivo con Emergencias.CSV", %{tmp_dir: dir} do
      ruta = Path.join(dir, Mensaje.archivo_csv())
      {:ok, entregado} = Mensaje.marcar_entregado(Fabrica.mensaje(id: "MS002"))
      mensajes = [Fabrica.mensaje(), entregado]

      :ok = CSV.escribir(ruta, Mensaje.cabecera_csv(), mensajes, &Mensaje.to_linea/1)

      assert {:ok, ^mensajes} = CSV.leer(ruta, &Mensaje.de_linea/1)
    end
  end
end
