import com.github._1c_syntax.bsl.mdclasses.CF;
import com.github._1c_syntax.bsl.mdclasses.MDCReadSettings;
import com.github._1c_syntax.bsl.mdclasses.MDClasses;
import com.github._1c_syntax.bsl.mdo.Form;
import com.github._1c_syntax.bsl.mdo.Module;
import com.github._1c_syntax.bsl.mdo.storage.form.FormEventHandler;
import com.github._1c_syntax.bsl.mdo.storage.form.FormEventHandlerOwner;
import com.github._1c_syntax.bsl.mdo.storage.form.FormItem;
import com.github._1c_syntax.bsl.types.MdoReference;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Читает каталог через MDClasses.createSolution (с теми же настройками, что BSL LS) и печатает
 * обработчики событий заимствованной формы в слитой конфигурации (Solution), в основе и в каждом
 * расширении, где форма есть. Обработчики — самой формы (FormData.getEventHandlers) и её
 * элементов (FormData.getPlainElements).
 * <p>
 * Аргументы: каталог с основой и расширением; необязательно — mdoRef формы и путь к модулю
 * этой формы в расширении относительно каталога. По умолчанию — форма из примера.
 */
public class FormHandlersProbe {

  public static void main(String[] args) {
    var root = Path.of(args[0]).toAbsolutePath().normalize();
    var formRef = MdoReference.create(args.length > 1 ? args[1] : "Document.Документ1.Form.ФормаДокумента");
    var extensionModule = args.length > 2 ? args[2] : "cfe/Documents/Документ1/Forms/ФормаДокумента/Ext/Form/Module.bsl";
    var solution = MDClasses.createSolution(root, MDCReadSettings.builder().skipDataCompositionSchema(true).build());

    var location = String.valueOf(MDClasses.class.getProtectionDomain().getCodeSource().getLocation());
    var jarName = Pattern.compile("mdclasses-[^/!]+\\.jar").matcher(location);
    out("mdclasses: " + (jarName.find() ? jarName.group() : location));
    out("Основа: " + solution.getBaseConfiguration().getName() + ", расширения: "
      + solution.getExtensions().stream().map(CF::getName).collect(Collectors.joining(", ")));
    out("Обработчики " + formRef.getMdoRef() + ":");

    var merged = form(solution, formRef);
    print("слитая (Solution)", merged, root);
    var base = form(solution.getBaseConfiguration(), formRef);
    if (base != null) {
      print("основа", base, root);
    }
    var lost = new ArrayList<FormEventHandler>();
    for (var extension : solution.getExtensions()) {
      var own = form(extension, formRef);
      if (own == null) {
        continue;
      }
      print("расширение " + extension.getName(), own, root);
      handlers(own).stream().filter(h -> !handlers(merged).contains(h)).forEach(lost::add);
    }

    var uri = root.resolve(extensionModule).toUri();
    var byUri = solution.findChild(uri).orElse(null);
    out("Solution.findChild(<" + extensionModule + ">) — "
      + (byUri == null ? "не найдено" : byUri.getMdoRef() + (byUri == merged ? ", это слитая форма" : "")));

    out("Итог: " + (lost.isEmpty()
      ? "у слитой формы есть все обработчики расширения — ошибка не воспроизводится"
      : "у слитой формы нет обработчиков расширения " + names(lost) + " — ошибка воспроизводится"));
  }

  private static Form form(CF cf, MdoReference formRef) {
    return (Form) cf.findChild(formRef).orElse(null);
  }

  private static List<FormEventHandler> handlers(Form form) {
    var data = form.getData();
    var result = new ArrayList<>(data.getEventHandlers());
    for (var element : data.getPlainElements()) {
      if (element instanceof FormEventHandlerOwner owner) {
        result.addAll(owner.getEventHandlers());
      }
    }
    return result;
  }

  private static void print(String label, Form form, Path root) {
    var data = form.getData();
    var elements = new ArrayList<String>();
    for (var element : data.getPlainElements()) {
      if (element instanceof FormEventHandlerOwner owner && !owner.getEventHandlers().isEmpty()) {
        elements.add(((FormItem) element).getName() + ": " + names(owner.getEventHandlers()));
      }
    }
    var modules = form.getModules().stream()
      .map(Module::getUri)
      .map(u -> root.relativize(Path.of(u)) + (Files.exists(Path.of(u)) ? "" : " (файла нет)"))
      .collect(Collectors.joining(", "));
    out("  " + label + ", " + form.getObjectBelonging().name() + ":");
    out("    форма:    " + names(data.getEventHandlers()));
    out("    элементы: " + (elements.isEmpty() ? "—" : String.join("; ", elements)));
    out("    модули:   " + modules);
  }

  private static String names(List<FormEventHandler> handlers) {
    return handlers.isEmpty()
      ? "—"
      : handlers.stream().map(h -> h.event() + " → " + h.handler()).collect(Collectors.joining(", "));
  }

  private static void out(String line) {
    System.out.println("| " + line);
  }
}
