defmodule Emergencias.CLI.ParserTest do
  use ExUnit.Case, async: true

  alias Emergencias.CLI.Parser

  @register "register_need agua 30 critica centro \"Punto sector 3\""

  describe "parsear/1: comandos válidos" do
    test "convierte los argumentos de un comando válido" do
      assert Parser.parsear(@register) ==
               {:ok, {:register_need, [:agua, 30, :critica, "centro", "Punto sector 3"]}}
    end

    test "respeta las comillas" do
      assert Parser.parsear("send_family_message 123 \"Estoy bien\"") ==
               {:ok, {:send_family_message, ["123", "Estoy bien"]}}
    end

    test "acepta saltos de línea de Windows y espacios sobrantes" do
      assert Parser.parsear("  send_family_message   123   \"Estoy bien\"\r\n") ==
               {:ok, {:send_family_message, ["123", "Estoy bien"]}}
    end

    test "el nombre del comando no distingue mayúsculas" do
      assert Parser.parsear("SEND_FAMILY_MESSAGE 123 hola") ==
               {:ok, {:send_family_message, ["123", "hola"]}}
    end

    test "sanitiza los textos (sin ';')" do
      assert Parser.parsear("send_family_message 123 \"Hola; mundo\"") ==
               {:ok, {:send_family_message, ["123", "Hola  mundo"]}}
    end

    test "la prioridad acepta critica y critico" do
      assert {:ok, {:register_need, [:agua, 30, :critica, _, _]}} =
               Parser.parsear("register_need agua 30 critico centro desc")

      assert {:ok, {:register_need, [:agua, 30, :critica, _, _]}} =
               Parser.parsear("register_need agua 30 CRITICA centro desc")
    end

    test "el tipo acepta otra:texto y guarda el texto aparte" do
      assert Parser.parsear("register_need otra:linternas 10 alta centro desc") ==
               {:ok, {:register_need, [{:otra, "linternas"}, 10, :alta, "centro", "desc"]}}
    end

    test "otra:texto admite espacios con comillas y más ':'" do
      assert {:ok, {:register_need, [{:otra, "pilas AA: 2 cajas"}, 1, :baja, _, _]}} =
               Parser.parsear("register_need \"otra:pilas AA: 2 cajas\" 1 baja centro desc")
    end
  end

  describe "parsear/1: errores de línea y de comando" do
    test "línea vacía" do
      assert Parser.parsear("") == {:error, :linea_vacia}
      assert Parser.parsear("   ") == {:error, :linea_vacia}
      assert Parser.parsear("\r\n") == {:error, :linea_vacia}
    end

    test "una línea que no es texto cuenta como vacía" do
      assert Parser.parsear(nil) == {:error, :linea_vacia}
    end

    test "comando desconocido" do
      assert Parser.parsear("hackear 1 2") == {:error, :comando_desconocido}
    end
  end

  describe "parsear/1: validación de argumentos" do
    test "faltan argumentos" do
      assert Parser.parsear("register_need agua 30") == {:error, {:argumentos, esperados: 5}}
    end

    test "sobran argumentos" do
      assert Parser.parsear("send_family_message 123 hola extra") ==
               {:error, {:argumentos, esperados: 2}}
    end

    test "comando sin argumentos cuando se esperan" do
      assert Parser.parsear("send_family_message") == {:error, {:argumentos, esperados: 2}}
    end

    test "entero inválido: letras, decimal y negativo" do
      assert Parser.parsear("register_need agua abc critica centro desc") ==
               {:error, {:valor_invalido, :cantidad}}

      assert Parser.parsear("register_need agua 3.5 critica centro desc") ==
               {:error, {:valor_invalido, :cantidad}}

      assert Parser.parsear("register_need agua -3 critica centro desc") ==
               {:error, {:valor_invalido, :cantidad}}
    end

    test "enumeración inválida (prioridad)" do
      assert Parser.parsear("register_need agua 30 urgente centro desc") ==
               {:error, {:valor_invalido, :prioridad}}
    end

    test "tipo de necesidad inválido" do
      assert Parser.parsear("register_need hack 30 critica centro desc") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "otra sin texto es inválido" do
      assert Parser.parsear("register_need otra 30 critica centro desc") ==
               {:error, {:valor_invalido, :tipo}}

      assert Parser.parsear("register_need otra: 30 critica centro desc") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "un prefijo distinto de otra con ':' es inválido" do
      assert Parser.parsear("register_need agua:x 30 critica centro desc") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "texto que queda vacío al sanitizar es inválido" do
      assert Parser.parsear("send_family_message 123 \";\"") ==
               {:error, {:valor_invalido, :mensaje}}
    end

    test "unas comillas vacías no cuentan como argumento (OptionParser las descarta)" do
      assert Parser.parsear("send_family_message 123 \"\"") ==
               {:error, {:argumentos, esperados: 2}}
    end

    test "informa el primer argumento inválido" do
      assert Parser.parsear("register_need hack abc urgente centro desc") ==
               {:error, {:valor_invalido, :tipo}}
    end
  end

  describe "parsear/1: filtros" do
    test "sin filtros devuelve una lista vacía" do
      assert Parser.parsear("list_needs") == {:ok, {:list_needs, []}}
    end

    test "filtros válidos en list_needs" do
      assert Parser.parsear("list_needs zona=centro prioridad=critico estado=pendiente") ==
               {:ok, {:list_needs, [zona: "centro", prioridad: :critica, estado: :pendiente]}}
    end

    test "list_needs acepta otra:texto en tipo" do
      assert Parser.parsear("list_needs tipo=otra:linternas") ==
               {:ok, {:list_needs, [tipo: {:otra, "linternas"}]}}
    end

    test "filtros válidos en list_resources" do
      assert Parser.parsear("list_resources categoria=agua zona=norte") ==
               {:ok, {:list_resources, [categoria: :agua, zona: "norte"]}}
    end

    test "filtros válidos en list_pets" do
      assert Parser.parsear("list_pets especie=perro estado=activa") ==
               {:ok, {:list_pets, [especie: "perro", estado: :activa]}}
    end

    test "list_pets ya no acepta color ni tamano (el servidor no los admite)" do
      assert Parser.parsear("list_pets color=negra") == {:error, {:filtro_invalido, "color"}}
      assert Parser.parsear("list_pets tamano=mediano") == {:error, {:filtro_invalido, "tamano"}}
    end

    test "filtros válidos en find_person, con comillas en el valor" do
      assert Parser.parsear("find_person nombre=\"Ana Maria\" estado=localizada") ==
               {:ok, {:find_person, [nombre: "Ana Maria", estado: :localizada]}}
    end

    test "clave desconocida" do
      assert Parser.parsear("list_needs color=rojo") ==
               {:error, {:filtro_invalido, "color"}}
    end

    test "una clave válida en otro comando es desconocida aquí" do
      assert Parser.parsear("list_resources prioridad=alta") ==
               {:error, {:filtro_invalido, "prioridad"}}
    end

    test "token sin '='" do
      assert Parser.parsear("list_needs centro") == {:error, {:filtro_invalido, "centro"}}
    end

    test "clave repetida" do
      assert Parser.parsear("list_needs zona=a zona=b") ==
               {:error, {:filtro_invalido, "zona"}}
    end

    test "valor de filtro inválido" do
      assert Parser.parsear("list_needs prioridad=urgente") ==
               {:error, {:valor_invalido, :prioridad}}

      assert Parser.parsear("list_pets zona=") == {:error, {:valor_invalido, :zona}}
    end

    test "una clave desconocida no crea átomos" do
      clave = "clave_inexistente_#{System.unique_integer([:positive])}"

      assert Parser.parsear("list_needs #{clave}=1") == {:error, {:filtro_invalido, clave}}

      assert_raise ArgumentError, fn -> String.to_existing_atom(clave) end
    end
  end

  describe "parsear_filtros/2" do
    @permitidos [zona: :texto, tamano: :tamano]

    test "devuelve una keyword list en el orden recibido" do
      assert Parser.parsear_filtros(["tamano=grande", "zona=centro"], @permitidos) ==
               {:ok, [tamano: :grande, zona: "centro"]}
    end

    test "lista vacía" do
      assert Parser.parsear_filtros([], @permitidos) == {:ok, []}
    end

    test "clave desconocida" do
      assert Parser.parsear_filtros(["otro=1"], @permitidos) ==
               {:error, {:filtro_invalido, "otro"}}
    end

    test "valor inválido" do
      assert Parser.parsear_filtros(["tamano=enorme"], @permitidos) ==
               {:error, {:valor_invalido, :tamano}}
    end

    test "argumentos que no son listas" do
      assert Parser.parsear_filtros("zona=centro", @permitidos) == {:error, :filtros_invalidos}
    end
  end

  describe "convertir/2" do
    test "texto" do
      assert Parser.convertir("  hola; mundo ", :texto) == {:ok, "hola  mundo"}
      assert Parser.convertir("   ", :texto) == {:error, :valor_invalido}
    end

    test "entero" do
      assert Parser.convertir("0", :entero) == {:ok, 0}
      assert Parser.convertir("-1", :entero) == {:error, :valor_invalido}
    end

    test "nivel acepta critico y critica" do
      assert Parser.convertir("critico", :nivel) == {:ok, :critico}
      assert Parser.convertir("critica", :nivel) == {:ok, :critico}
      assert Parser.convertir("extremo", :nivel) == {:error, :valor_invalido}
    end

    test "prioridad acepta critica y critico" do
      assert Parser.convertir("critica", :prioridad) == {:ok, :critica}
      assert Parser.convertir("critico", :prioridad) == {:ok, :critica}
      assert Parser.convertir("extrema", :prioridad) == {:error, :valor_invalido}
    end

    test "tipo de usuario" do
      assert Parser.convertir("Coordinador", :tipo_usuario) == {:ok, :coordinador}
      assert Parser.convertir("jefe", :tipo_usuario) == {:error, :valor_invalido}
    end

    test "categoría y tipo de necesidad" do
      assert Parser.convertir("agua", :categoria) == {:ok, :agua}
      assert Parser.convertir("otra:linternas", :categoria) == {:ok, {:otra, "linternas"}}
      assert Parser.convertir("otra:linternas", :tipo_necesidad) == {:ok, {:otra, "linternas"}}
      assert Parser.convertir("lava", :categoria) == {:error, :valor_invalido}
    end

    test "estado de necesidad" do
      assert Parser.convertir("pendiente", :estado_necesidad) == {:ok, :pendiente}
      assert Parser.convertir("hecho", :estado_necesidad) == {:error, :valor_invalido}
    end

    test "estado de persona" do
      assert Parser.convertir("localizada", :estado_persona) == {:ok, :localizada}
      assert Parser.convertir("EN_ALBERGUE", :estado_persona) == {:ok, :en_albergue}
      assert Parser.convertir("perdida", :estado_persona) == {:error, :valor_invalido}
      assert Parser.convertir("albergada", :estado_persona) == {:error, :valor_invalido}
    end

    test "estado de mascota" do
      assert Parser.convertir("posible_coincidencia", :estado_mascota) ==
               {:ok, :posible_coincidencia}

      assert Parser.convertir("cerrada", :estado_mascota) == {:error, :valor_invalido}
    end

    test "tipo de mascota acepta lost/found y perdida/encontrada" do
      assert Parser.convertir("lost", :tipo_mascota) == {:ok, :perdida}
      assert Parser.convertir("LOST", :tipo_mascota) == {:ok, :perdida}
      assert Parser.convertir("perdida", :tipo_mascota) == {:ok, :perdida}
      assert Parser.convertir("found", :tipo_mascota) == {:ok, :encontrada}
      assert Parser.convertir("encontrada", :tipo_mascota) == {:ok, :encontrada}
      assert Parser.convertir("robada", :tipo_mascota) == {:error, :valor_invalido}
      assert Parser.convertir(nil, :tipo_mascota) == {:error, :valor_invalido}
    end

    test "tamaño" do
      assert Parser.convertir("mediano", :tamano) == {:ok, :mediano}
      assert Parser.convertir("gigante", :tamano) == {:error, :valor_invalido}
    end

    test "tipo desconocido y valor que no es texto" do
      assert Parser.convertir("x", :no_existe) == {:error, :tipo_invalido}
      assert Parser.convertir(nil, :texto) == {:error, :valor_invalido}
    end
  end

  describe "connect" do
    test "válido (ejemplo del issue)" do
      assert Parser.parsear("connect laura 1234 coordinador centro") ==
               {:ok, {:connect, ["laura", "1234", :coordinador, "centro"]}}
    end

    test "el tipo no distingue mayúsculas" do
      assert Parser.parsear("connect ana 1234 VOLUNTARIO centro") ==
               {:ok, {:connect, ["ana", "1234", :voluntario, "centro"]}}
    end

    test "inválido: tipo de usuario" do
      assert Parser.parsear("connect laura 1234 rey centro") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "inválido: faltan argumentos" do
      assert Parser.parsear("connect laura 1234") == {:error, {:argumentos, esperados: 4}}
    end
  end

  describe "disconnect" do
    test "válido: no recibe argumentos" do
      assert Parser.parsear("disconnect") == {:ok, {:disconnect, []}}
    end

    test "inválido: sobran argumentos" do
      assert Parser.parsear("disconnect ahora") == {:error, {:argumentos, esperados: 0}}
    end
  end

  describe "register_zone" do
    test "válido (ejemplo del issue)" do
      assert Parser.parsear("register_zone centro \"Zona Centro\" critico") ==
               {:ok, {:register_zone, ["centro", "Zona Centro", :critico]}}
    end

    test "el nivel acepta critica y critico" do
      assert Parser.parsear("register_zone centro Centro critica") ==
               {:ok, {:register_zone, ["centro", "Centro", :critico]}}
    end

    test "inválido: nivel" do
      assert Parser.parsear("register_zone centro Centro enorme") ==
               {:error, {:valor_invalido, :nivel}}
    end

    test "inválido: faltan argumentos" do
      assert Parser.parsear("register_zone centro") == {:error, {:argumentos, esperados: 3}}
    end
  end

  describe "register_sector" do
    test "válido (ejemplo del issue)" do
      assert Parser.parsear("register_sector centro S1 \"Sector 1\" 200") ==
               {:ok, {:register_sector, ["centro", "S1", "Sector 1", 200]}}
    end

    test "inválido: personas no es un número" do
      assert Parser.parsear("register_sector centro S1 Sector abc") ==
               {:error, {:valor_invalido, :personas}}
    end

    test "inválido: personas negativo" do
      assert Parser.parsear("register_sector centro S1 Sector -1") ==
               {:error, {:valor_invalido, :personas}}
    end

    test "inválido: faltan argumentos" do
      assert Parser.parsear("register_sector centro S1") ==
               {:error, {:argumentos, esperados: 4}}
    end
  end

  describe "register_point" do
    test "válido (ejemplo del issue)" do
      assert Parser.parsear("register_point centro S1 P1 \"Punto 3\" 40") ==
               {:ok, {:register_point, ["centro", "S1", "P1", "Punto 3", 40]}}
    end

    test "inválido: personas no es un número" do
      assert Parser.parsear("register_point centro S1 P1 Punto 3.5") ==
               {:error, {:valor_invalido, :personas}}
    end

    test "inválido: faltan argumentos" do
      assert Parser.parsear("register_point centro S1 P1") ==
               {:error, {:argumentos, esperados: 5}}
    end
  end

  describe "zone_status y zone_stats" do
    test "zone_status válido" do
      assert Parser.parsear("zone_status centro") == {:ok, {:zone_status, ["centro"]}}
    end

    test "zone_stats válido" do
      assert Parser.parsear("zone_stats centro") == {:ok, {:zone_stats, ["centro"]}}
    end

    test "inválido: sin zona" do
      assert Parser.parsear("zone_status") == {:error, {:argumentos, esperados: 1}}
      assert Parser.parsear("zone_stats") == {:error, {:argumentos, esperados: 1}}
    end

    test "inválido: sobran argumentos" do
      assert Parser.parsear("zone_stats centro norte") ==
               {:error, {:argumentos, esperados: 1}}
    end
  end

  describe "register_need: orden de los argumentos" do
    test "la zona va antes que la descripción (igual que Comandos y help)" do
      assert Parser.parsear("register_need agua 30 critica norte \"Sin agua\"") ==
               {:ok, {:register_need, [:agua, 30, :critica, "norte", "Sin agua"]}}
    end
  end

  describe "comandos de necesidades y recursos" do
    test "pending_needs y critical_resources no reciben argumentos" do
      assert Parser.parsear("pending_needs") == {:ok, {:pending_needs, []}}
      assert Parser.parsear("critical_resources") == {:ok, {:critical_resources, []}}

      assert Parser.parsear("pending_needs x") == {:error, {:argumentos, esperados: 0}}
      assert Parser.parsear("critical_resources x") == {:error, {:argumentos, esperados: 0}}
    end

    test "set_need_status válido e inválido" do
      assert Parser.parsear("set_need_status N001 en_proceso") ==
               {:ok, {:set_need_status, ["N001", :en_proceso]}}

      assert Parser.parsear("set_need_status N001 hecho") ==
               {:error, {:valor_invalido, :estado}}

      assert Parser.parsear("set_need_status N001") == {:error, {:argumentos, esperados: 2}}
    end

    test "cancel_need válido e inválido" do
      assert Parser.parsear("cancel_need N001") == {:ok, {:cancel_need, ["N001"]}}
      assert Parser.parsear("cancel_need") == {:error, {:argumentos, esperados: 1}}
    end

    test "assign_resource válido e inválido" do
      assert Parser.parsear("assign_resource N001 agua 20") ==
               {:ok, {:assign_resource, ["N001", :agua, 20]}}

      assert Parser.parsear("assign_resource N001 lava 20") ==
               {:error, {:valor_invalido, :categoria}}

      assert Parser.parsear("assign_resource N001 agua -1") ==
               {:error, {:valor_invalido, :cantidad}}

      assert Parser.parsear("assign_resource N001 agua") ==
               {:error, {:argumentos, esperados: 3}}
    end

    test "register_resource con y sin zona" do
      assert Parser.parsear("register_resource R001 agua 50 litros centro_acopio_1") ==
               {:ok, {:register_resource, ["R001", :agua, 50, "litros", "centro_acopio_1"]}}

      assert Parser.parsear("register_resource R001 agua 50 litros centro_acopio_1 norte") ==
               {:ok,
                {:register_resource, ["R001", :agua, 50, "litros", "centro_acopio_1", "norte"]}}
    end

    test "register_resource inválido: cantidad de argumentos y valores" do
      assert Parser.parsear("register_resource R001 agua 50 litros") ==
               {:error, {:argumentos, esperados: 5}}

      assert Parser.parsear("register_resource R001 agua 50 litros c1 norte extra") ==
               {:error, {:argumentos, esperados: 5}}

      assert Parser.parsear("register_resource R001 agua abc litros c1") ==
               {:error, {:valor_invalido, :cantidad}}
    end

    test "add_stock y remove_stock" do
      assert Parser.parsear("add_stock R001 10") == {:ok, {:add_stock, ["R001", 10]}}
      assert Parser.parsear("remove_stock R001 10") == {:ok, {:remove_stock, ["R001", 10]}}
      assert Parser.parsear("add_stock R001 diez") == {:error, {:valor_invalido, :cantidad}}
      assert Parser.parsear("remove_stock R001") == {:error, {:argumentos, esperados: 2}}
    end

    test "transfer_resource válido e inválido" do
      assert Parser.parsear("transfer_resource R001 centro_1 centro_2 15") ==
               {:ok, {:transfer_resource, ["R001", "centro_1", "centro_2", 15]}}

      assert Parser.parsear("transfer_resource R001 centro_1 centro_2 -5") ==
               {:error, {:valor_invalido, :cantidad}}

      assert Parser.parsear("transfer_resource R001 centro_1") ==
               {:error, {:argumentos, esperados: 4}}
    end
  end

  describe "report_person" do
    test "válido" do
      assert Parser.parsear("report_person 1094 Andrés 30 centro localizada") ==
               {:ok, {:report_person, ["1094", "Andrés", 30, "centro", :localizada]}}
    end

    test "el estado acepta los de Persona" do
      assert {:ok, {:report_person, [_, _, _, _, :en_albergue]}} =
               Parser.parsear("report_person 1094 Ana 30 centro en_albergue")
    end

    test "inválido: estado" do
      assert Parser.parsear("report_person 1094 Ana 30 centro albergada") ==
               {:error, {:valor_invalido, :estado}}
    end

    test "inválido: edad" do
      assert Parser.parsear("report_person 1094 Ana abc centro localizada") ==
               {:error, {:valor_invalido, :edad}}

      assert Parser.parsear("report_person 1094 Ana -3 centro localizada") ==
               {:error, {:valor_invalido, :edad}}
    end

    test "inválido: cantidad de argumentos" do
      assert Parser.parsear("report_person 1094 Ana") == {:error, {:argumentos, esperados: 5}}
    end
  end

  describe "find_person" do
    test "un documento suelto" do
      assert Parser.parsear("find_person 1094") == {:ok, {:find_person, ["1094"]}}
    end

    test "sin argumentos devuelve filtros vacíos" do
      assert Parser.parsear("find_person") == {:ok, {:find_person, []}}
    end

    test "filtros, incluso uno solo" do
      assert Parser.parsear("find_person zona=centro") ==
               {:ok, {:find_person, [zona: "centro"]}}
    end

    test "inválido: dos tokens sin '='" do
      assert Parser.parsear("find_person 1094 1095") == {:error, {:filtro_invalido, "1094"}}
    end

    test "inválido: documento que queda vacío al sanitizar" do
      assert Parser.parsear("find_person \";\"") == {:error, {:valor_invalido, :documento}}
    end

    test "inválido: estado de persona en un filtro" do
      assert Parser.parsear("find_person estado=albergada") ==
               {:error, {:valor_invalido, :estado}}
    end
  end

  describe "set_person_state" do
    test "válido" do
      assert Parser.parsear("set_person_state 1094 en_albergue") ==
               {:ok, {:set_person_state, ["1094", :en_albergue]}}
    end

    test "inválido: estado" do
      assert Parser.parsear("set_person_state 1094 volando") ==
               {:error, {:valor_invalido, :estado}}
    end

    test "inválido: cantidad de argumentos" do
      assert Parser.parsear("set_person_state 1094") == {:error, {:argumentos, esperados: 2}}
    end
  end

  describe "list_family_messages y mark_message_delivered" do
    test "list_family_messages válido e inválido" do
      assert Parser.parsear("list_family_messages 1094") ==
               {:ok, {:list_family_messages, ["1094"]}}

      assert Parser.parsear("list_family_messages") == {:error, {:argumentos, esperados: 1}}
    end

    test "mark_message_delivered válido e inválido" do
      assert Parser.parsear("mark_message_delivered MS001") ==
               {:ok, {:mark_message_delivered, ["MS001"]}}

      assert Parser.parsear("mark_message_delivered") == {:error, {:argumentos, esperados: 1}}
    end
  end

  describe "report_pet" do
    test "válido: lost, sin características" do
      assert Parser.parsear("report_pet lost perro Luna negra mediano centro 3001234567") ==
               {:ok,
                {:report_pet,
                 [:perdida, "perro", "Luna", "negra", :mediano, "centro", "3001234567"]}}
    end

    test "válido: found, con características entre comillas" do
      assert Parser.parsear(
               "report_pet found gato desconocido gris pequeno centro 3001234567 \"collar rojo\""
             ) ==
               {:ok,
                {:report_pet,
                 [
                   :encontrada,
                   "gato",
                   "desconocido",
                   "gris",
                   :pequeno,
                   "centro",
                   "3001234567",
                   "collar rojo"
                 ]}}
    end

    test "inválido: tipo" do
      assert Parser.parsear("report_pet robada perro Luna negra mediano centro 300") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "inválido: tamaño" do
      assert Parser.parsear("report_pet lost perro Luna negra gigante centro 300") ==
               {:error, {:valor_invalido, :tamano}}
    end

    test "inválido: cantidad de argumentos (menos de 7 o más de 8)" do
      assert Parser.parsear("report_pet lost perro") == {:error, {:argumentos, esperados: 7}}

      assert Parser.parsear("report_pet lost perro Luna negra mediano centro 300 a b") ==
               {:error, {:argumentos, esperados: 7}}
    end
  end

  describe "match_pets y confirm_pet_match" do
    test "match_pets válido e inválido" do
      assert Parser.parsear("match_pets") == {:ok, {:match_pets, []}}
      assert Parser.parsear("match_pets x") == {:error, {:argumentos, esperados: 0}}
    end

    test "confirm_pet_match válido e inválido" do
      assert Parser.parsear("confirm_pet_match M001 M002") ==
               {:ok, {:confirm_pet_match, ["M001", "M002"]}}

      assert Parser.parsear("confirm_pet_match M001") == {:error, {:argumentos, esperados: 2}}
    end
  end

  describe "register_shelter" do
    test "válido: sin ocupación" do
      assert Parser.parsear("register_shelter A01 \"Albergue Norte\" centro 100") ==
               {:ok, {:register_shelter, ["A01", "Albergue Norte", "centro", 100]}}
    end

    test "válido: con ocupación" do
      assert Parser.parsear("register_shelter A01 Norte centro 100 40") ==
               {:ok, {:register_shelter, ["A01", "Norte", "centro", 100, 40]}}
    end

    test "inválido: capacidad y ocupación" do
      assert Parser.parsear("register_shelter A01 Norte centro cien") ==
               {:error, {:valor_invalido, :capacidad}}

      assert Parser.parsear("register_shelter A01 Norte centro 100 -1") ==
               {:error, {:valor_invalido, :ocupacion}}
    end

    test "inválido: cantidad de argumentos (menos de 4 o más de 5)" do
      assert Parser.parsear("register_shelter A01 Norte centro") ==
               {:error, {:argumentos, esperados: 4}}

      assert Parser.parsear("register_shelter A01 Norte centro 100 0 sobra") ==
               {:error, {:argumentos, esperados: 4}}
    end
  end

  describe "check_shelter, register_entry y register_exit" do
    test "check_shelter válido e inválido" do
      assert Parser.parsear("check_shelter A01") == {:ok, {:check_shelter, ["A01"]}}
      assert Parser.parsear("check_shelter") == {:error, {:argumentos, esperados: 1}}
    end

    test "register_entry válido e inválido" do
      assert Parser.parsear("register_entry A01 1094") ==
               {:ok, {:register_entry, ["A01", "1094"]}}

      assert Parser.parsear("register_entry A01") == {:error, {:argumentos, esperados: 2}}
    end

    test "register_exit válido e inválido" do
      assert Parser.parsear("register_exit A01 1094") ==
               {:ok, {:register_exit, ["A01", "1094"]}}

      assert Parser.parsear("register_exit A01") == {:error, {:argumentos, esperados: 2}}
    end
  end

  describe "shelter_report y summary" do
    test "shelter_report con y sin n" do
      assert Parser.parsear("shelter_report") == {:ok, {:shelter_report, []}}
      assert Parser.parsear("shelter_report 3") == {:ok, {:shelter_report, [3]}}
    end

    test "shelter_report inválido: n no es un entero no negativo" do
      assert Parser.parsear("shelter_report tres") == {:error, {:valor_invalido, :n}}
      assert Parser.parsear("shelter_report -1") == {:error, {:valor_invalido, :n}}
    end

    test "shelter_report inválido: más de un argumento" do
      assert Parser.parsear("shelter_report 1 2") == {:error, {:argumentos, esperados: 0}}
    end

    test "summary válido e inválido" do
      assert Parser.parsear("summary") == {:ok, {:summary, []}}
      assert Parser.parsear("summary x") == {:error, {:argumentos, esperados: 0}}
    end
  end

  describe "help y exit" do
    test "válidos" do
      assert Parser.parsear("help") == {:ok, {:help, []}}
      assert Parser.parsear("exit") == {:ok, {:exit, []}}
    end

    test "inválido: sobran argumentos" do
      assert Parser.parsear("exit ahora") == {:error, {:argumentos, esperados: 0}}
    end
  end
end
