defmodule Emergencias.PersistenciaTest do
  # No es async: cambia `:data_dir` del entorno de la aplicación.
  use ExUnit.Case

  alias Emergencias.CSV
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Dominio.Movimiento
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Persona
  alias Emergencias.Dominio.PuntoAtencion
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Sector
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Dominio.Zona
  alias Emergencias.Persistencia

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    anterior = Application.fetch_env(:emergencias, :data_dir)
    Application.put_env(:emergencias, :data_dir, tmp_dir)

    on_exit(fn ->
      case anterior do
        {:ok, valor} -> Application.put_env(:emergencias, :data_dir, valor)
        :error -> Application.delete_env(:emergencias, :data_dir)
      end
    end)

    :ok
  end

  # Construye una entidad con su función `crear`; si falla, la prueba falla aquí.
  defp ok!({:ok, valor}), do: valor

  defp zona_con_arbol(codigo, nombre, sectores) do
    zona = ok!(Zona.crear(codigo, nombre, :alto, 500))

    Enum.reduce(sectores, zona, fn {cod_sector, nombre_sector, puntos}, zona ->
      sector =
        Enum.reduce(puntos, ok!(Sector.crear(cod_sector, nombre_sector, 40)), fn {cod, nom},
                                                                                 sector ->
          ok!(Sector.agregar_punto(sector, ok!(PuntoAtencion.crear(cod, nom, 10))))
        end)

      ok!(Zona.agregar_sector(zona, sector))
    end)
  end

  describe "archivos inexistentes" do
    test "cada cargar devuelve una lista vacía" do
      assert Persistencia.cargar_usuarios() == {:ok, []}
      assert Persistencia.cargar_zonas() == {:ok, []}
      assert Persistencia.cargar_necesidades() == {:ok, []}
      assert Persistencia.cargar_recursos() == {:ok, []}
      assert Persistencia.cargar_mascotas() == {:ok, []}
      assert Persistencia.cargar_mensajes() == {:ok, []}
      assert Persistencia.cargar_personas() == {:ok, []}
    end
  end

  describe "usuarios" do
    test "ida y vuelta; `conectado` no se guarda" do
      ana = ok!(Usuario.crear("ana", "clave1", "Ana Gómez", :coordinador, "centro"))
      luis = ok!(Usuario.crear("luis", "clave2", "Luis Pérez", :ciudadano, "norte"))

      assert :ok = Persistencia.guardar_usuarios([Usuario.conectar(ana), luis])
      assert {:ok, [^ana, ^luis]} = Persistencia.cargar_usuarios()
    end

    test "guardar de nuevo reemplaza el contenido anterior" do
      ana = ok!(Usuario.crear("ana", "clave1", "Ana Gómez", :coordinador, "centro"))
      luis = ok!(Usuario.crear("luis", "clave2", "Luis Pérez", :ciudadano, "norte"))

      assert :ok = Persistencia.guardar_usuarios([ana, luis])
      assert :ok = Persistencia.guardar_usuarios([luis])
      assert {:ok, [^luis]} = Persistencia.cargar_usuarios()
    end

    test "lista vacía deja un archivo que se carga como lista vacía" do
      assert :ok = Persistencia.guardar_usuarios([])
      assert File.exists?(CSV.ruta("usuarios.csv"))
      assert {:ok, []} = Persistencia.cargar_usuarios()
    end

    test "guardar rechaza algo que no es una lista de usuarios" do
      assert {:error, :lista_invalida} = Persistencia.guardar_usuarios(:no_es_lista)
      assert {:error, :lista_invalida} = Persistencia.guardar_usuarios([%{username: "x"}])
      refute File.exists?(CSV.ruta("usuarios.csv"))
    end

    test "cargar informa la línea corrupta" do
      File.write!(
        CSV.ruta("usuarios.csv"),
        Usuario.cabecera() <> "\nana;HASH;Ana;ciudadano;centro\nlinea rota\n"
      )

      assert {:error, {:linea_invalida, 3}} = Persistencia.cargar_usuarios()
    end
  end

  describe "zonas" do
    test "una zona con 2 sectores y 3 puntos se reconstruye igual" do
      zona =
        zona_con_arbol("centro", "Centro", [
          {"S1", "Sector uno", [{"P1", "Colegio"}, {"P2", "Parque"}]},
          {"S2", "Sector dos", [{"P3", "Coliseo"}]}
        ])

      assert length(zona.sectores) == 2
      assert zona |> Zona.estadisticas() |> Map.fetch!(:num_puntos) == 3

      assert :ok = Persistencia.guardar_zonas([zona])
      assert {:ok, [^zona]} = Persistencia.cargar_zonas()
    end

    test "escribe una fila por zona, sector y punto con las columnas del issue" do
      zona =
        zona_con_arbol("centro", "Centro", [
          {"S1", "Sector uno", [{"P1", "Colegio"}, {"P2", "Parque"}]},
          {"S2", "Sector dos", [{"P3", "Coliseo"}]}
        ])

      assert :ok = Persistencia.guardar_zonas([zona])

      assert File.read!(CSV.ruta("zonas.csv")) ==
               "codigo;nombre;nivel;personas\ncentro;Centro;alto;500\n"

      assert File.read!(CSV.ruta("sectores.csv")) ==
               "zona;codigo;nombre;personas\ncentro;S1;Sector uno;40\ncentro;S2;Sector dos;40\n"

      assert File.read!(CSV.ruta("puntos.csv")) ==
               "zona;sector;codigo;nombre;personas\n" <>
                 "centro;S1;P1;Colegio;10\ncentro;S1;P2;Parque;10\ncentro;S2;P3;Coliseo;10\n"
    end

    test "varias zonas conservan el orden y no mezclan sectores con el mismo código" do
      norte = zona_con_arbol("norte", "Norte", [{"S1", "Norte uno", [{"P1", "Iglesia"}]}])

      sur =
        zona_con_arbol("sur", "Sur", [
          {"S1", "Sur uno", [{"P1", "Escuela"}]},
          {"S2", "Sur dos", []}
        ])

      vacia = ok!(Zona.crear("este", "Este", :bajo, 0))

      assert :ok = Persistencia.guardar_zonas([norte, sur, vacia])
      assert {:ok, [^norte, ^sur, ^vacia]} = Persistencia.cargar_zonas()
    end

    test "guardar de nuevo reemplaza el árbol anterior" do
      zona = zona_con_arbol("centro", "Centro", [{"S1", "Sector uno", [{"P1", "Colegio"}]}])
      sin_sectores = ok!(Zona.crear("centro", "Centro", :alto, 500))

      assert :ok = Persistencia.guardar_zonas([zona])
      assert :ok = Persistencia.guardar_zonas([sin_sectores])
      assert {:ok, [^sin_sectores]} = Persistencia.cargar_zonas()
    end

    test "guardar rechaza listas que no son de zonas" do
      assert {:error, :lista_invalida} = Persistencia.guardar_zonas(:no_es_lista)
      assert {:error, :lista_invalida} = Persistencia.guardar_zonas([:no_es_zona])

      zona_rota = %{ok!(Zona.crear("centro", "Centro", :alto, 1)) | sectores: [:no_es_sector]}
      assert {:error, :lista_invalida} = Persistencia.guardar_zonas([zona_rota])

      sector_roto = %{ok!(Sector.crear("S1", "Uno", 1)) | puntos_atencion: [:no_es_punto]}

      zona_con_sector_roto = %{
        ok!(Zona.crear("centro", "Centro", :alto, 1))
        | sectores: [sector_roto]
      }

      assert {:error, :lista_invalida} = Persistencia.guardar_zonas([zona_con_sector_roto])

      refute File.exists?(CSV.ruta("zonas.csv"))
    end

    test "cargar informa una línea corrupta en cualquiera de los tres archivos" do
      File.write!(
        CSV.ruta("zonas.csv"),
        "codigo;nombre;nivel;personas\ncentro;Centro;nivel_raro;5\n"
      )

      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_zonas()

      File.write!(CSV.ruta("zonas.csv"), "codigo;nombre;nivel;personas\ncentro;Centro;alto;5\n")
      File.write!(CSV.ruta("sectores.csv"), "zona;codigo;nombre;personas\ncentro;S1;Uno\n")
      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_zonas()

      File.write!(CSV.ruta("sectores.csv"), "zona;codigo;nombre;personas\ncentro;S1;Uno;4\n")

      File.write!(
        CSV.ruta("puntos.csv"),
        "zona;sector;codigo;nombre;personas\ncentro;S1;P1;Colegio;x\n"
      )

      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_zonas()
    end

    test "un sector con zona inexistente da :sector_huerfano" do
      File.write!(CSV.ruta("zonas.csv"), "codigo;nombre;nivel;personas\ncentro;Centro;alto;5\n")
      File.write!(CSV.ruta("sectores.csv"), "zona;codigo;nombre;personas\nnorte;S1;Uno;4\n")

      assert {:error, :sector_huerfano} = Persistencia.cargar_zonas()
    end

    test "un punto con sector inexistente en su zona da :punto_huerfano" do
      File.write!(CSV.ruta("zonas.csv"), "codigo;nombre;nivel;personas\ncentro;Centro;alto;5\n")
      File.write!(CSV.ruta("sectores.csv"), "zona;codigo;nombre;personas\ncentro;S1;Uno;4\n")

      File.write!(
        CSV.ruta("puntos.csv"),
        "zona;sector;codigo;nombre;personas\ncentro;S9;P1;Colegio;2\n"
      )

      assert {:error, :punto_huerfano} = Persistencia.cargar_zonas()
    end
  end

  describe "necesidades" do
    test "ida y vuelta, incluida una de tipo :otra asociada a un albergue" do
      agua =
        ok!(Necesidad.crear("N001", :agua, nil, "Agua potable", 100, "centro", :critica, "ana"))

      otra =
        ok!(
          Necesidad.crear(
            "N002",
            :otra,
            "Pañales",
            "Pañales para bebés",
            20,
            "norte",
            :alta,
            "luis",
            asociada_a: {:albergue, "A01"}
          )
        )

      assert :ok = Persistencia.guardar_necesidades([agua, otra])
      assert {:ok, [^agua, ^otra]} = Persistencia.cargar_necesidades()
    end

    test "lista inválida y línea corrupta" do
      assert {:error, :lista_invalida} = Persistencia.guardar_necesidades([:no_es_necesidad])

      File.write!(CSV.ruta(Necesidad.archivo()), Necesidad.cabecera() <> "\nlinea rota\n")
      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_necesidades()
    end
  end

  describe "recursos" do
    test "ida y vuelta" do
      agua =
        ok!(Recurso.crear("R001", "Agua embotellada", :agua, 300, "litros", "bodega", "centro"))

      kit =
        ok!(Recurso.crear("R002", "Botiquín", :primeros_auxilios, 0, "unidades", "sede", "norte"))

      assert :ok = Persistencia.guardar_recursos([agua, kit])
      assert {:ok, [^agua, ^kit]} = Persistencia.cargar_recursos()
    end

    test "lista inválida y línea corrupta" do
      assert {:error, :lista_invalida} = Persistencia.guardar_recursos([:no_es_recurso])

      File.write!(
        CSV.ruta("recursos.csv"),
        Recurso.cabecera() <> "\nR001;Agua;categoria_rara;5;l;b;c\n"
      )

      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_recursos()
    end
  end

  describe "mascotas" do
    test "ida y vuelta, con y sin nombre y con estado distinto de :activa" do
      perra =
        ok!(
          Mascota.crear(
            "M001",
            :perdida,
            "perro",
            "Luna",
            "collar rojo",
            "negra",
            :mediano,
            "centro",
            "3001112222"
          )
        )

      gato =
        ok!(
          Mascota.crear(
            "M002",
            :encontrada,
            "gato",
            nil,
            nil,
            "gris",
            :pequeno,
            "norte",
            "3003334444"
          )
        )

      resuelta = %{gato | id: "M003", estado: :resuelta}

      assert :ok = Persistencia.guardar_mascotas([perra, gato, resuelta])
      assert {:ok, [^perra, ^gato, ^resuelta]} = Persistencia.cargar_mascotas()
    end

    test "lista inválida y línea corrupta" do
      assert {:error, :lista_invalida} = Persistencia.guardar_mascotas([:no_es_mascota])

      File.write!(CSV.ruta(Mascota.archivo()), Mascota.cabecera() <> "\nlinea rota\n")
      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_mascotas()
    end
  end

  describe "mensajes" do
    test "ida y vuelta en estado :pendiente y :entregado" do
      pendiente = ok!(Mensaje.crear("MS001", "ana", "1094", "Estamos bien, te buscamos"))
      entregado = %{ok!(Mensaje.crear("MS002", "luis", "2001", "Ya voy")) | estado: :entregado}

      assert :ok = Persistencia.guardar_mensajes([pendiente, entregado])
      assert {:ok, [^pendiente, ^entregado]} = Persistencia.cargar_mensajes()
    end

    test "lista inválida y línea corrupta" do
      assert {:error, :lista_invalida} = Persistencia.guardar_mensajes([:no_es_mensaje])

      File.write!(CSV.ruta(Mensaje.archivo_csv()), Mensaje.cabecera_csv() <> "\nlinea rota\n")
      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_mensajes()
    end
  end

  describe "personas" do
    test "ida y vuelta: el historial se une a cada persona por documento" do
      andres = ok!(Persona.crear("1094", "Andrés", 30, "centro", :reportada, "laura"))
      andres = ok!(Persona.cambiar_estado(andres, :localizada, "pedro"))
      andres = ok!(Persona.cambiar_estado(andres, :en_albergue, "laura"))
      marta = ok!(Persona.crear("2001", "Marta", 8, "norte", :sin_informacion, "pedro"))

      assert length(andres.historial) == 3

      assert :ok = Persistencia.guardar_personas([andres, marta])
      assert {:ok, [^andres, ^marta]} = Persistencia.cargar_personas()
    end

    test "escribe personas.csv e historial_personas.csv" do
      andres = ok!(Persona.crear("1094", "Andrés", 30, "centro", :reportada, "laura"))
      andres = ok!(Persona.cambiar_estado(andres, :localizada, "pedro"))

      assert :ok = Persistencia.guardar_personas([andres])

      assert File.read!(CSV.ruta("personas.csv")) ==
               "documento;nombre;edad;zona;estado\n1094;Andrés;30;centro;localizada\n"

      [cabecera, primera, segunda] =
        CSV.ruta("historial_personas.csv") |> File.read!() |> String.split("\n", trim: true)

      assert cabecera == "documento;fecha;de;a;usuario"
      assert String.ends_with?(primera, ";;reportada;laura")
      assert String.ends_with?(segunda, ";reportada;localizada;pedro")
    end

    test "ignora historial de un documento que no está en personas.csv" do
      marta = ok!(Persona.crear("2001", "Marta", 8, "norte", :sin_informacion, "pedro"))
      assert :ok = Persistencia.guardar_personas([marta])

      CSV.agregar(
        CSV.ruta("historial_personas.csv"),
        Persona.cabecera_historial_csv(),
        {"9999", %{fecha: "2026-01-01T00:00:00Z", de: nil, a: :reportada, usuario: "x"}},
        &Persona.historial_to_linea/1
      )

      assert {:ok, [^marta]} = Persistencia.cargar_personas()
    end

    test "lista inválida y líneas corruptas en cualquiera de los dos archivos" do
      assert {:error, :lista_invalida} = Persistencia.guardar_personas([:no_es_persona])

      File.write!(CSV.ruta("personas.csv"), Persona.cabecera_csv() <> "\nlinea rota\n")
      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_personas()

      File.write!(
        CSV.ruta("personas.csv"),
        Persona.cabecera_csv() <> "\n1094;Andrés;30;centro;localizada\n"
      )

      File.write!(
        CSV.ruta("historial_personas.csv"),
        Persona.cabecera_historial_csv() <> "\n1094;2026-01-01T00:00:00Z;;estado_raro;laura\n"
      )

      assert {:error, {:linea_invalida, 2}} = Persistencia.cargar_personas()
    end
  end

  describe "movimientos (solo se agrega al final)" do
    defp movimiento(id, tipo, cantidad, referencia) do
      mov = ok!(Movimiento.nuevo("R001", tipo, cantidad, "ana", referencia))
      %{mov | id: id}
    end

    test "crea el archivo con cabecera y agrega sin reescribir" do
      primero = movimiento("MOV001", :entrada, 50, nil)
      segundo = movimiento("MOV002", :asignacion, 10, "N001")

      assert :ok = Persistencia.agregar_movimiento(primero)
      assert :ok = Persistencia.agregar_movimiento(segundo)

      lineas = CSV.ruta("movimientos.csv") |> File.read!() |> String.split("\n", trim: true)
      assert hd(lineas) == Movimiento.cabecera()
      assert length(lineas) == 3

      assert {:ok, [^primero, ^segundo]} =
               CSV.leer(CSV.ruta("movimientos.csv"), &Movimiento.de_linea/1)
    end

    test "rechaza un movimiento sin id" do
      sin_id = ok!(Movimiento.nuevo("R001", :entrada, 5, "ana", nil))

      assert {:error, :id_requerido} = Persistencia.agregar_movimiento(sin_id)
      assert {:error, :id_requerido} = Persistencia.agregar_movimiento(%{sin_id | id: "  "})
      refute File.exists?(CSV.ruta("movimientos.csv"))
    end

    test "rechaza algo que no es un movimiento" do
      assert {:error, :movimiento_invalido} = Persistencia.agregar_movimiento(%{id: "MOV001"})
    end
  end

  describe "errores del sistema de archivos" do
    test "guardar devuelve {:error, razon} si la carpeta no se puede crear", %{tmp_dir: tmp_dir} do
      bloqueo = Path.join(tmp_dir, "bloqueo")
      File.write!(bloqueo, "soy un archivo, no una carpeta")
      Application.put_env(:emergencias, :data_dir, bloqueo)

      ana = ok!(Usuario.crear("ana", "clave1", "Ana Gómez", :coordinador, "centro"))

      assert {:error, _razon} = Persistencia.guardar_usuarios([ana])
      assert {:error, _razon} = Persistencia.guardar_zonas([])
    end
  end
end
