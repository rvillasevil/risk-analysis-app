class RenameDatosIdentificativosToIdentificacion < ActiveRecord::Migration[7.0]
  def change
    rename_table :datos_identificativos, :identificacions
  end
end
