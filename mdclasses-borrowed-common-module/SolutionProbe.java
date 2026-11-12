import com.github._1c_syntax.bsl.mdclasses.CF;
import com.github._1c_syntax.bsl.mdclasses.MDCReadSettings;
import com.github._1c_syntax.bsl.mdclasses.MDClasses;
import com.github._1c_syntax.bsl.mdo.MD;
import com.github._1c_syntax.bsl.mdo.Module;
import com.github._1c_syntax.bsl.mdo.ModuleOwner;
import com.github._1c_syntax.bsl.types.MdoReference;
import com.github._1c_syntax.bsl.types.ModuleType;

import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Читает каталог через MDClasses.createSolution (с теми же настройками, что BSL LS) и печатает,
 * что о каждом BSL-файле знают решение и само расширение, и модули объектов в слитой конфигурации.
 * Последняя строка — итог: «ошибка воспроизводится — <невыполненные условия>»,
 * «ошибка не воспроизводится — выполнены все условия» или «сбой — <причина>».
 * Аргумент: каталог примера (with-base-bsl или without-base-bsl).
 */
public class SolutionProbe {

  private static final String BORROWED_MODULE = "cfe/CommonModules/ОбщийМодуль1/Ext/Module.bsl";
  private static final String BASE_MODULE = "cf/CommonModules/ОбщийМодуль1/Ext/Module.bsl";
  private static final String COMMON_MODULE = "CommonModule.ОбщийМодуль1";

  public static void main(String[] args) throws IOException {
    var root = Path.of(args[0]).toAbsolutePath().normalize();
    var solution = MDClasses.createSolution(root, MDCReadSettings.builder().skipDataCompositionSchema(true).build());

    var location = String.valueOf(MDClasses.class.getProtectionDomain().getCodeSource().getLocation());
    var jarName = Pattern.compile("mdclasses-[^/!]+\\.jar").matcher(location);
    out("mdclasses: " + (jarName.find() ? jarName.group() : location));
    if (solution.getExtensions().size() != 1) {
      out("Итог: сбой — в решении " + solution.getExtensions().size() + " расширений, ожидалось одно");
      return;
    }
    var extension = solution.getExtensions().get(0);
    out("Основа: " + solution.getBaseConfiguration().getName() + ", расширение: " + extension.getName());

    out(String.format("%-52s %-34s %-20s %s", "Файл", "Solution.findChild(uri)", "getModuleTypeByURI", "расширение.findChild(uri)"));
    List<Path> files;
    try (Stream<Path> stream = Files.walk(root)) {
      files = stream.filter(p -> p.toString().endsWith(".bsl")).sorted().toList();
    }
    for (var file : files) {
      var uri = file.toUri();
      out(String.format("%-52s %-34s %-20s %s", root.relativize(file), ref(solution, uri),
        solution.getModuleTypeByURI(uri), ref(extension, uri)));
    }

    out("Модули объектов в слитой конфигурации, getModules():");
    for (var name : List.of(COMMON_MODULE, "Document.Документ1")) {
      var found = solution.findChild(MdoReference.create(name));
      if (found.isEmpty() || !(found.get() instanceof ModuleOwner owner)) {
        out("  " + name + ": нет в слитой конфигурации");
        continue;
      }
      var modules = owner.getModules().stream()
        .map(Module::getUri)
        .map(uri -> root.relativize(Path.of(uri)) + (Files.exists(Path.of(uri)) ? "" : " (файла нет)"))
        .collect(Collectors.joining(", "));
      out("  " + name + ": " + modules);
    }

    out("Итог: " + verdict(root, solution, extension));
  }

  /**
   * Ошибка исправлена, только когда выполнены все три условия для модуля расширения:
   * решение находит его объект, знает его тип и держит его среди модулей слитого общего модуля.
   * Если BSL основы есть на диске, среди модулей должен остаться и модуль основы.
   */
  private static String verdict(Path root, CF solution, CF extension) {
    var uri = root.resolve(BORROWED_MODULE).toUri();
    if (extension.findChild(uri).isEmpty()) {
      return "сбой — расширение не знает " + BORROWED_MODULE + ", пример прочитан не так";
    }
    var merged = solution.findChild(MdoReference.create(COMMON_MODULE));
    if (merged.isEmpty() || !(merged.get() instanceof ModuleOwner owner)) {
      return "сбой — в слитой конфигурации нет " + COMMON_MODULE;
    }
    var failed = new ArrayList<String>();
    var found = ref(solution, uri);
    if (!COMMON_MODULE.equals(found)) {
      failed.add("Solution.findChild(uri) = " + found + ", нужно " + COMMON_MODULE);
    }
    var type = solution.getModuleTypeByURI(uri);
    if (type != ModuleType.CommonModule) {
      failed.add("getModuleTypeByURI(uri) = " + type + ", нужно CommonModule");
    }
    var moduleUris = owner.getModules().stream().map(Module::getUri).toList();
    if (!moduleUris.contains(uri)) {
      failed.add("среди модулей слитого " + COMMON_MODULE + " нет " + BORROWED_MODULE);
    }
    var base = root.resolve(BASE_MODULE);
    if (Files.exists(base) && !moduleUris.contains(base.toUri())) {
      failed.add("среди модулей слитого " + COMMON_MODULE + " нет " + BASE_MODULE);
    }
    return failed.isEmpty()
      ? "ошибка не воспроизводится — выполнены все условия"
      : "ошибка воспроизводится — " + String.join("; ", failed);
  }

  private static String ref(CF cf, URI uri) {
    return cf.findChild(uri).map(MD::getMdoRef).orElse("—");
  }

  private static void out(String line) {
    System.out.println("| " + line);
  }
}
