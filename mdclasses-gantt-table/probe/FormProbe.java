import com.github._1c_syntax.bsl.mdclasses.MDCReadSettings;
import com.github._1c_syntax.bsl.mdclasses.MDClasses;
import com.github._1c_syntax.bsl.mdo.Form;
import com.github._1c_syntax.bsl.mdo.storage.form.FormElement;
import com.github._1c_syntax.bsl.mdo.storage.form.FormElementOwner;
import com.github._1c_syntax.bsl.mdo.storage.form.FormEventHandler;
import com.github._1c_syntax.bsl.mdo.storage.form.FormEventHandlerOwner;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Читает каталог выгрузки конфигуратора через mdclasses с теми же настройками, что BSL LS
 * (skipDataCompositionSchema), и для каждой управляемой формы печатает:
 * - дерево getElements() с типом элемента, классом модели и событиями;
 * - плоский список getPlainElements() с событиями — из него BSL LS собирает обработчики;
 * - есть ли в getPlainElements() элементы, переданные аргументами.
 * Аргументы: каталог [имя элемента ...]. Системное свойство probe.form — подстрока mdoRef формы
 * для отбора (по умолчанию все формы). Код выхода: 0 — все элементы найдены, 1 — какого-то нет.
 */
public class FormProbe {

  public static void main(String[] args) {
    var root = Path.of(args[0]).toAbsolutePath().normalize();
    var expected = Arrays.asList(args).subList(1, args.length);
    var settings = MDCReadSettings.builder().skipDataCompositionSchema(true).build();
    var cf = MDClasses.createConfiguration(root, settings);

    var missing = new ArrayList<String>();
    var formFilter = System.getProperty("probe.form", "");
    var forms = cf.getPlainChildren().stream()
      .filter(Form.class::isInstance)
      .map(Form.class::cast)
      .filter(form -> form.getMdoRef().contains(formFilter))
      .toList();
    for (var form : forms) {
      var data = form.getData();
      System.out.println("| Форма " + form.getMdoRef());
      System.out.println("|   getElements(), дерево:");
      printTree(data.getElements(), "|     ");
      var plain = data.getPlainElements();
      System.out.println("|   getPlainElements(): " + plain.size() + " элементов, события есть у "
        + plain.stream().filter(FormProbe::hasHandlers).count());
      for (var element : plain) {
        if (hasHandlers(element)) {
          System.out.println("|     " + element.getName() + ": " + handlers(element));
        }
      }
      for (var name : expected) {
        var found = plain.stream().anyMatch(element -> element.getName().equals(name));
        System.out.println("|   " + name + " в getPlainElements(): " + (found ? "есть" : "НЕТ"));
        if (!found) {
          missing.add(name);
        }
      }
    }
    if (missing.isEmpty()) {
      System.out.println("| Итог: все элементы на месте");
    } else {
      System.out.println("| Итог: mdclasses потеряла элементы " + String.join(", ", missing));
      System.exit(1);
    }
  }

  private static void printTree(List<FormElement> elements, String indent) {
    for (var element : elements) {
      var line = indent + element.getName() + " [" + element.getType().nameEn() + ", "
        + element.getClass().getSimpleName() + "]";
      if (hasHandlers(element)) {
        line += " " + handlers(element);
      }
      System.out.println(line);
      if (element instanceof FormElementOwner owner) {
        printTree(owner.getElements(), indent + "  ");
      }
    }
  }

  private static boolean hasHandlers(FormElement element) {
    return element instanceof FormEventHandlerOwner owner && !owner.getEventHandlers().isEmpty();
  }

  private static String handlers(FormElement element) {
    List<FormEventHandler> handlers = ((FormEventHandlerOwner) element).getEventHandlers();
    return handlers.stream()
      .map(handler -> handler.event() + " -> " + handler.handler())
      .collect(Collectors.joining(", "));
  }
}
