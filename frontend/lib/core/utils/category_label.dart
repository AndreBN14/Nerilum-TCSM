/// Traduce las etiquetas del modelo de clasificación de demencia
/// al español para mostrarlas en la interfaz.
///
/// La función devuelve la etiqueta localizada si es conocida;
/// de lo contrario devuelve el valor original sin modificar.
String categoryLabel(String raw) {
  switch (raw.toLowerCase()) {
    case 'nondemented':
      return 'Sin demencia';
    case 'verymilddemented':
      return 'Demencia muy leve';
    case 'milddemented':
      return 'Demencia leve';
    case 'moderatedemented':
      return 'Demencia moderada';
    default:
      return raw;
  }
}
