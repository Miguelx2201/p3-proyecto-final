defmodule Emergencias.Servicios.ReportesServicio do
  @moduledoc """
  Reportes y estadísticas del sistema (funciones puras).

  Todas las funciones reciben listas de entidades del dominio y devuelven datos
  (listas, números o mapas). No guardan estado, no modifican las entidades y no
  escriben en pantalla: mostrar los resultados es trabajo de la interfaz.
  """

  alias Emergencias.Dominio.Albergue
  alias Emergencias.Dominio.Mascota
  alias Emergencias.Dominio.Mensaje
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Dominio.Persona
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Dominio.Zona
  alias Emergencias.Servicios.Ordenamiento

  # Prioridades de `Necesidad`, de mayor a menor. El módulo de dominio no las
  # expone con una función pública, por eso se repiten aquí.
  @prioridades [:critica, :alta, :media, :baja]

  # Estados cerrados de `Necesidad` (mismo caso: no hay función pública).
  @necesidad_cerrada [:atendida, :cancelada]

  # Una persona cuenta como localizada desde `:localizada` en adelante
  # (`:localizada`, `:trasladada`, `:en_albergue`, `:reunificada`).
  @estados_localizada Enum.drop_while(Persona.estados(), &(&1 != :localizada))

  @type recurso_critico :: %{
          zona: String.t(),
          categoria: Recurso.categoria(),
          disponible: non_neg_integer(),
          demanda: pos_integer(),
          deficit: pos_integer()
        }

  # ---------------------------------------------------------------------------
  # Albergues
  # ---------------------------------------------------------------------------

  @doc """
  Los `n` albergues con mayor porcentaje de ocupación
  (`Albergue.porcentaje_ocupacion/1`), de mayor a menor.

  Ordena con `Ordenamiento.ordenar/2`, que es estable: si dos albergues tienen
  el mismo porcentaje conservan el orden en que llegaron. Si hay menos de `n`
  albergues devuelve todos. `n` debe ser un entero mayor o igual a 0.
  """
  @spec albergues_mas_ocupados([Albergue.t()], non_neg_integer()) :: [Albergue.t()]
  def albergues_mas_ocupados(albergues, n \\ 5)
      when is_list(albergues) and is_integer(n) and n >= 0 do
    albergues
    |> Enum.map(fn albergue -> {Albergue.porcentaje_ocupacion(albergue), albergue} end)
    |> Ordenamiento.ordenar(fn {porcentaje_a, _a}, {porcentaje_b, _b} ->
      porcentaje_a > porcentaje_b
    end)
    |> Enum.take(n)
    |> Enum.map(fn {_porcentaje, albergue} -> albergue end)
  end

  # ---------------------------------------------------------------------------
  # Recursos
  # ---------------------------------------------------------------------------

  @doc """
  Suma la `cantidad_disponible` de los recursos de la `categoria` y la `zona`
  dadas (comparación exacta). Si ninguno coincide devuelve 0.
  """
  @spec disponibilidad([Recurso.t()], Recurso.categoria(), String.t()) :: non_neg_integer()
  def disponibilidad(recursos, categoria, zona) when is_list(recursos) do
    Enum.reduce(recursos, 0, fn
      %Recurso{categoria: ^categoria, zona: ^zona, cantidad_disponible: cantidad}, total ->
        total + cantidad

      _otro, total ->
        total
    end)
  end

  @doc """
  Recursos críticos: pares `{zona, categoria}` cuya disponibilidad no alcanza
  para cubrir la demanda.

  La demanda de un par es la suma de `Necesidad.cantidad_faltante/1` de las
  necesidades **no cerradas** (ni `:atendida` ni `:cancelada`) cuyo `tipo` es
  esa categoría y cuya `zona` es esa zona. El disponible es
  `disponibilidad/3` del mismo par. Un par es crítico si
  `disponible < demanda`.

  Devuelve una lista de mapas
  `%{zona, categoria, disponible, demanda, deficit}` (con
  `deficit = demanda - disponible`), solo con los pares críticos, ordenada de
  mayor a menor déficit; los empates se ordenan por zona y luego por categoría.
  """
  @spec recursos_criticos([Recurso.t()], [Necesidad.t()]) :: [recurso_critico()]
  def recursos_criticos(recursos, necesidades)
      when is_list(recursos) and is_list(necesidades) do
    necesidades
    |> demanda_por_par()
    |> Enum.map(fn {{zona, categoria}, demanda} ->
      disponible = disponibilidad(recursos, categoria, zona)

      %{
        zona: zona,
        categoria: categoria,
        disponible: disponible,
        demanda: demanda,
        deficit: demanda - disponible
      }
    end)
    |> Enum.filter(fn par -> par.disponible < par.demanda end)
    |> Ordenamiento.ordenar(&antes_por_deficit?/2)
  end

  # Mapa `{zona, tipo} => suma de cantidad_faltante` de las necesidades abiertas.
  defp demanda_por_par(necesidades) do
    Enum.reduce(necesidades, %{}, fn
      %Necesidad{estado: estado} = necesidad, demandas when estado not in @necesidad_cerrada ->
        faltante = Necesidad.cantidad_faltante(necesidad)
        Map.update(demandas, {necesidad.zona, necesidad.tipo}, faltante, &(&1 + faltante))

      _otra, demandas ->
        demandas
    end)
  end

  defp antes_por_deficit?(a, b) do
    a.deficit > b.deficit or
      (a.deficit == b.deficit and {a.zona, a.categoria} < {b.zona, b.categoria})
  end

  # ---------------------------------------------------------------------------
  # Resumen global
  # ---------------------------------------------------------------------------

  @doc """
  Resumen de todo el sistema.

  `datos` es un mapa con las listas `zonas`, `necesidades`, `recursos`,
  `personas`, `mensajes`, `mascotas` y `albergues`. Una clave que falte se toma
  como lista vacía.

  Devuelve un mapa con:

    * `recursos_por_categoria`: `%{categoria => total disponible}` con todas las
      categorías de `Recurso.categorias/0` (las que no tienen recursos en 0).
    * `necesidades_pendientes`: `%{prioridad => conteo}` de las necesidades en
      estado `:pendiente`, con las cuatro prioridades (en 0 si no hay).
    * `personas_localizadas`: personas en estado `:localizada` o posterior
      (`:trasladada`, `:en_albergue`, `:reunificada`).
    * `mensajes`: `%{total, pendientes}`.
    * `mascotas`: `%{activas, posibles, resueltas}` (estados `:activa`,
      `:posible_coincidencia` y `:resuelta`).
    * `albergues`: `%{capacidad_total, ocupacion_total}`.
    * `zonas`: lista `%{codigo, nombre, nivel, personas}` en el orden recibido,
      donde `personas` es `Zona.total_personas/1`.
  """
  @spec resumen_global(map()) :: map()
  def resumen_global(datos) when is_map(datos) do
    zonas = Map.get(datos, :zonas, [])
    necesidades = Map.get(datos, :necesidades, [])
    recursos = Map.get(datos, :recursos, [])
    personas = Map.get(datos, :personas, [])
    mensajes = Map.get(datos, :mensajes, [])
    mascotas = Map.get(datos, :mascotas, [])
    albergues = Map.get(datos, :albergues, [])

    %{
      recursos_por_categoria: recursos_por_categoria(recursos),
      necesidades_pendientes: necesidades_pendientes(necesidades),
      personas_localizadas:
        Enum.count(personas, fn
          %Persona{estado: estado} -> estado in @estados_localizada
          _otra -> false
        end),
      mensajes: resumen_mensajes(mensajes),
      mascotas: resumen_mascotas(mascotas),
      albergues: resumen_albergues(albergues),
      zonas: resumen_zonas(zonas)
    }
  end

  defp recursos_por_categoria(recursos) do
    inicial = Map.new(Recurso.categorias(), fn categoria -> {categoria, 0} end)

    Enum.reduce(recursos, inicial, fn
      %Recurso{categoria: categoria, cantidad_disponible: cantidad}, totales ->
        Map.update(totales, categoria, cantidad, &(&1 + cantidad))

      _otro, totales ->
        totales
    end)
  end

  defp necesidades_pendientes(necesidades) do
    inicial = Map.new(@prioridades, fn prioridad -> {prioridad, 0} end)

    Enum.reduce(necesidades, inicial, fn
      %Necesidad{estado: :pendiente, prioridad: prioridad}, conteo ->
        Map.update(conteo, prioridad, 1, &(&1 + 1))

      _otra, conteo ->
        conteo
    end)
  end

  defp resumen_mensajes(mensajes) do
    %{
      total: Enum.count(mensajes, &match?(%Mensaje{}, &1)),
      pendientes: Enum.count(mensajes, &match?(%Mensaje{estado: :pendiente}, &1))
    }
  end

  defp resumen_mascotas(mascotas) do
    %{
      activas: Enum.count(mascotas, &match?(%Mascota{estado: :activa}, &1)),
      posibles: Enum.count(mascotas, &match?(%Mascota{estado: :posible_coincidencia}, &1)),
      resueltas: Enum.count(mascotas, &match?(%Mascota{estado: :resuelta}, &1))
    }
  end

  defp resumen_albergues(albergues) do
    Enum.reduce(albergues, %{capacidad_total: 0, ocupacion_total: 0}, fn
      %Albergue{} = albergue, totales ->
        %{
          capacidad_total: totales.capacidad_total + albergue.capacidad_maxima,
          ocupacion_total: totales.ocupacion_total + albergue.ocupacion_actual
        }

      _otro, totales ->
        totales
    end)
  end

  defp resumen_zonas(zonas) do
    for %Zona{} = zona <- zonas do
      %{
        codigo: zona.codigo,
        nombre: zona.nombre,
        nivel: zona.nivel,
        personas: Zona.total_personas(zona)
      }
    end
  end
end
