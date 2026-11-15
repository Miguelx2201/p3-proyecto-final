defmodule Emergencias.CLI.ParserTest do
  use ExUnit.Case, async: true

  alias Emergencias.CLI.Parser

  @register "register_need agua 30 critica \"Punto sector 3\" centro"

  describe "parsear/1: comandos válidos" do
    test "convierte los argumentos de un comando válido" do
      assert Parser.parsear(@register) ==
               {:ok, {:register_need, [:agua, 30, :critica, "Punto sector 3", "centro"]}}
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
               Parser.parsear("register_need agua 30 critico desc centro")

      assert {:ok, {:register_need, [:agua, 30, :critica, _, _]}} =
               Parser.parsear("register_need agua 30 CRITICA desc centro")
    end

    test "el tipo acepta otra:texto y guarda el texto aparte" do
      assert Parser.parsear("register_need otra:linternas 10 alta desc centro") ==
               {:ok, {:register_need, [{:otra, "linternas"}, 10, :alta, "desc", "centro"]}}
    end

    test "otra:texto admite espacios con comillas y más ':'" do
      assert {:ok, {:register_need, [{:otra, "pilas AA: 2 cajas"}, 1, :baja, _, _]}} =
               Parser.parsear("register_need \"otra:pilas AA: 2 cajas\" 1 baja desc centro")
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
      assert Parser.parsear("register_need agua abc critica desc centro") ==
               {:error, {:valor_invalido, :cantidad}}

      assert Parser.parsear("register_need agua 3.5 critica desc centro") ==
               {:error, {:valor_invalido, :cantidad}}

      assert Parser.parsear("register_need agua -3 critica desc centro") ==
               {:error, {:valor_invalido, :cantidad}}
    end

    test "enumeración inválida (prioridad)" do
      assert Parser.parsear("register_need agua 30 urgente desc centro") ==
               {:error, {:valor_invalido, :prioridad}}
    end

    test "tipo de necesidad inválido" do
      assert Parser.parsear("register_need hack 30 critica desc centro") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "otra sin texto es inválido" do
      assert Parser.parsear("register_need otra 30 critica desc centro") ==
               {:error, {:valor_invalido, :tipo}}

      assert Parser.parsear("register_need otra: 30 critica desc centro") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "un prefijo distinto de otra con ':' es inválido" do
      assert Parser.parsear("register_need agua:x 30 critica desc centro") ==
               {:error, {:valor_invalido, :tipo}}
    end

    test "texto vacío es inválido" do
      assert Parser.parsear("send_family_message 123 \"\"") ==
               {:error, {:valor_invalido, :mensaje}}
    end

    test "informa el primer argumento inválido" do
      assert Parser.parsear("register_need hack abc urgente desc centro") ==
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
      assert Parser.parsear("list_pets especie=perro tamano=mediano") ==
               {:ok, {:list_pets, [especie: "perro", tamano: :mediano]}}
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
      assert Parser.convertir("perdida", :estado_persona) == {:error, :valor_invalido}
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
end
