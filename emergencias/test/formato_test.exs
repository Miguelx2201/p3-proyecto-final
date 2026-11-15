defmodule Emergencias.CLI.FormatoTest do
  use ExUnit.Case, async: true

  alias Emergencias.CLI.Formato
  alias Emergencias.Dominio.Albergue
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Persona
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Usuario
  alias Emergencias.Dominio.Zona
  alias Emergencias.Servicios.ReportesServicio

  # ---------------------------------------------------------------------------
  # Ayudas
  # ---------------------------------------------------------------------------

  defp usuario(tipo) do
    {:ok, usuario} = Usuario.crear("u_#{tipo}", "1234", "Usuario de prueba", tipo, "centro")
    usuario
  end

  defp zona do
    {:ok, zona} = Zona.crear("centro", "Zona Centro", :critico, 500)
    zona
  end

  defp necesidad do
    {:ok, necesidad} =
      Necesidad.crear("N001", :agua, nil, "Punto sector 3", 30, "centro", :critica, "laura")

    necesidad
  end

  defp recurso do
    {:ok, recurso} =
      Recurso.crear("R001", "agua", :agua, 50, "litros", "centro_acopio_1", "centro")

    recurso
  end

  defp persona do
    {:ok, persona} = Persona.crear("1094", "Andrés Pérez", 34, "centro", :localizada, "laura")
    persona
  end

  defp mensaje do
    {:ok, mensaje} = Mensaje.crear("MS001", "laura", "1094", "Estamos bien")
    mensaje
  end

  defp mascota(id, tipo) do
    {:ok, mascota} =
      Mascota.crear(id, tipo, "perro", "Firulais", "collar", "negro", :mediano, "centro", "300")

    mascota
  end

  defp albergue do
    {:ok, albergue} = Albergue.crear("A01", "Albergue Norte", "centro", 100, 30)
    albergue
  end

  # ---------------------------------------------------------------------------
  # Errores
  # ---------------------------------------------------------------------------

  describe "a_texto/1 con errores" do
    test "usa el mapa de razones" do
      assert Formato.a_texto({:error, :sin_stock}) == "No hay suficiente inventario."
      assert Formato.a_texto({:error, :permiso_denegado}) =~ "permiso"
      assert Formato.a_texto({:error, :no_conectado}) =~ "connect"
      assert Formato.a_texto({:error, :credenciales_invalidas}) =~ "contraseña"
    end

    test "una razón desconocida se muestra legible" do
      assert Formato.a_texto({:error, :razon_rara}) == "Error: razon rara."
    end

    test "errores del parser" do
      assert Formato.a_texto({:error, {:argumentos, esperados: 0}}) ==
               "Este comando no recibe argumentos."

      assert Formato.a_texto({:error, {:argumentos, esperados: 1}}) =~ "1 argumento."
      assert Formato.a_texto({:error, {:argumentos, esperados: 4}}) =~ "4 argumentos"
      assert Formato.a_texto({:error, {:valor_invalido, :tipo}}) =~ "«tipo»"
      assert Formato.a_texto({:error, {:filtro_invalido, "foo"}}) =~ "«foo»"
      assert Formato.a_texto({:error, :linea_vacia}) =~ "help"
      assert Formato.a_texto({:error, :comando_desconocido}) =~ "help"
    end

    test "nunca falla con formas inesperadas" do
      assert is_binary(Formato.a_texto({:error, {:rara, 1, 2}}))
      assert is_binary(Formato.a_texto({:error, "texto"}))
      assert is_binary(Formato.a_texto(:cualquier_cosa))
      assert is_binary(Formato.a_texto(nil))
    end
  end

  # ---------------------------------------------------------------------------
  # Valores
  # ---------------------------------------------------------------------------

  describe "a_texto/1 con resultados correctos" do
    test ":ok da una confirmación" do
      assert Formato.a_texto(:ok) == "Operación realizada."
    end

    test "una lista vacía" do
      assert Formato.a_texto({:ok, []}) == "No se encontraron resultados."
    end

    test "una lista de entidades usa to_string/1, una por línea" do
      lista = [
        necesidad(),
        recurso(),
        persona(),
        mensaje(),
        albergue(),
        mascota("M001", :perdida)
      ]

      assert Formato.a_texto({:ok, lista}) == Enum.map_join(lista, "\n", &to_string/1)
    end

    test "un texto se muestra tal cual" do
      assert Formato.a_texto({:ok, "hola"}) == "hola"
    end

    test "una sola entidad" do
      assert Formato.a_texto({:ok, albergue()}) == to_string(albergue())
    end

    test "el usuario conectado" do
      assert Formato.a_texto({:ok, usuario(:coordinador)}) ==
               "Sesión iniciada: " <> to_string(usuario(:coordinador))
    end

    test "una zona muestra sus sectores y puntos" do
      sector =
        struct(Emergencias.Dominio.Sector,
          codigo: "S1",
          nombre: "Sector 1",
          personas_afectadas: 200,
          puntos_atencion: [
            struct(Emergencias.Dominio.PuntoAtencion,
              codigo: "P1",
              nombre: "Punto 3",
              personas_afectadas: 40
            )
          ]
        )

      zona = %{zona() | sectores: [sector]}
      texto = Formato.a_texto({:ok, zona})

      assert texto =~ "Zona centro - Zona Centro"
      assert texto =~ "Sector S1 - Sector 1: 200 personas"
      assert texto =~ "Punto P1 - Punto 3: 40 personas"
    end

    test "una zona sin sectores es una sola línea" do
      assert Formato.a_texto({:ok, zona()}) == to_string(zona())
    end

    test "estadísticas de zona" do
      texto = Formato.a_texto({:ok, Zona.estadisticas(zona())})

      assert texto =~ "Estadísticas de la zona:"
      assert texto =~ "Personas estimadas de la zona: 500"
      assert texto =~ "Sectores: 0"
    end

    test "recursos críticos" do
      criticos = [%{zona: "centro", categoria: :agua, disponible: 20, demanda: 30, deficit: 10}]

      assert Formato.a_texto({:ok, criticos}) ==
               "centro / agua: disponible 20, demanda 30, déficit 10"
    end

    test "coincidencias de mascotas" do
      pares = [%{perdida_id: "M001", encontrada_id: "M002", puntaje: 7}]

      assert Formato.a_texto({:ok, pares}) == "M001 <-> M002 (puntaje: 7)"
    end

    test "confirmación de coincidencia" do
      texto =
        Formato.a_texto({:ok, {mascota("M001", :perdida), mascota("M002", :encontrada)}})

      assert texto =~ "Coincidencia confirmada"
      assert texto =~ "M001 [perdida]"
      assert texto =~ "M002 [encontrada]"
    end

    test "asignación de recursos" do
      n = necesidad()
      texto = Formato.a_texto({:ok, %{necesidad: n, movimientos: [%{}, %{}]}})

      assert texto =~ "Asignación registrada (2 movimiento(s)"
      assert texto =~ to_string(n)
    end

    test "un valor desconocido no falla" do
      assert Formato.a_texto({:ok, {:algo, 1}}) == "{:algo, 1}"
      assert Formato.a_texto({:ok, 42}) == "42"
    end
  end

  describe "a_texto/1 con el resumen" do
    test "se presenta por secciones" do
      resumen =
        ReportesServicio.resumen_global(%{
          zonas: [zona()],
          necesidades: [necesidad()],
          recursos: [recurso()],
          personas: [persona()],
          mensajes: [mensaje()],
          mascotas: [mascota("M001", :perdida)],
          albergues: [albergue()]
        })

      texto = Formato.a_texto({:ok, resumen})

      for titulo <- [
            "Recursos disponibles",
            "Necesidades pendientes",
            "Personas",
            "Mensajes",
            "Mascotas",
            "Albergues",
            "Zonas"
          ] do
        assert texto =~ "=== #{titulo} ==="
      end

      assert texto =~ "agua: 50"
      assert texto =~ "critica: 1"
      assert texto =~ "Personas localizadas: 1"
      assert texto =~ "Pendientes: 1"
      assert texto =~ "Activas: 1"
      assert texto =~ "Capacidad total: 100"
      assert texto =~ "Ocupación total: 30"
      assert texto =~ "[centro] Zona Centro (critico)"
    end

    test "un sistema vacío también se presenta" do
      texto = Formato.a_texto({:ok, ReportesServicio.resumen_global(%{})})

      assert texto =~ "=== Zonas ==="
      assert texto =~ "No hay zonas registradas."
      assert texto =~ "Personas localizadas: 0"
    end
  end

  # ---------------------------------------------------------------------------
  # Ayuda
  # ---------------------------------------------------------------------------

  describe "ayuda/1" do
    test "sin sesión solo muestra connect, help y exit" do
      texto = Formato.ayuda(nil)

      assert texto =~ "connect usuario contrasena tipo zona"
      assert texto =~ "  help"
      assert texto =~ "  exit"
      refute texto =~ "disconnect"
      refute texto =~ "register_need"
      refute texto =~ "register_zone"
      refute texto =~ "summary"
    end

    test "un ciudadano ve solo lo permitido para su rol" do
      texto = Formato.ayuda(usuario(:ciudadano))

      assert texto =~ "Comandos disponibles para ciudadano:"
      assert texto =~ "register_need tipo cantidad prioridad zona descripcion"
      assert texto =~ "zone_status zona"
      assert texto =~ "disconnect"
      assert texto =~ "  exit"
      refute texto =~ "list_resources"
      refute texto =~ "register_zone"
      refute texto =~ "add_stock"
      refute texto =~ "summary"
    end

    test "un voluntario suma sus comandos pero no los de coordinador" do
      texto = Formato.ayuda(usuario(:voluntario))

      assert texto =~ "list_resources"
      assert texto =~ "set_person_state"
      assert texto =~ "match_pets"
      refute texto =~ "register_zone"
      refute texto =~ "assign_resource"
    end

    test "un coordinador ve los comandos de gestión" do
      texto = Formato.ayuda(usuario(:coordinador))

      assert texto =~ "register_zone codigo nombre nivel"
      assert texto =~ "assign_resource id categoria cantidad"
      assert texto =~ "summary"
    end

    test "un administrador ve todo" do
      texto = Formato.ayuda(usuario(:administrador))

      assert texto =~ "register_zone"
      assert texto =~ "critical_resources"
      assert texto =~ "shelter_report"
      assert texto =~ "summary"
    end

    test "una sesión inválida no falla y se trata como sin sesión" do
      assert Formato.ayuda(:basura) == Formato.ayuda(nil)
    end
  end

  describe "mensajes fijos" do
    test "bienvenida, sesión cerrada y despedida" do
      assert Formato.bienvenida() =~ "help"
      assert Formato.sesion_cerrada() == "Sesión cerrada."
      assert Formato.despedida() == "Hasta luego."
    end
  end
end
