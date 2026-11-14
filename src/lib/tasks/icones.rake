# Refaz os ícones do tema do EasyUI a partir dos originais do Lucide (lib/icones.rb). Rodar depois de mudar o mapa `Icones::DO_TEMA`.
namespace :crm do
  namespace :icones do
    desc "Grava os ícones do tema do EasyUI (vendor/assets/easyui/tema/images) a partir dos originais do Lucide"
    task tema: :environment do
      Icones.gravar_tema!
      puts "#{Icones.arquivos_do_tema.size} ícones do tema gravados em #{Icones::TEMA}"
    end
  end
end
