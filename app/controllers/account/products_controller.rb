class Account::ProductsController < AccountController

    before_action :set_octokit_client, only: [:index, :edit, :update, :import]
    before_action :set_product, only: [:edit, :update, :destroy, :delete_digital_product,:delete_screenshot]

    # --------------------------------------------------------------------------
    # VIEWS
    # --------------------------------------------------------------------------

    def index
        @products = current_user.products.all
        @github_repositories = Octokit.repositories(Octokit.user)
    end

    # --------------------------------------------------------------------------

    def edit
        unless current_user.github_token.nil?
            unless @product.github_repo_id.nil?

                begin
                    @github_repo = Octokit.repo(current_user.github_login+"/"+@product.github_repo_name)
                    @commits = Octokit.commits(@github_repo.id)
                    @last_commit = @commits[0]['sha']
                rescue Octokit::Error => e
                    redirect_to account_products_path, alert: 'Your repository is not available. We cannot edit your product.'
                    return
                end
            end
        end
    end

    # --------------------------------------------------------------------------
    # ACTIONS
    # --------------------------------------------------------------------------

    # Import a repository from Github and save it as a product

    def import_github

        require 'open-uri'

        if current_user.products.exists?(github_repo_id: params[:repo_id])
            redirect_to account_products_path, notice: 'A product is already linked to this repository'
            return
        end

        if current_user.github_token.nil?
            redirect_to account_products_path, notice: 'Your account should be linked to a GitHub Account'
            return
        end

        # Récupération de l'utilisateur
        begin
            @user = Octokit.user
        rescue Octokit::Error => e
            redirect_to account_products_path, alert: 'No Github user found. Please verify your Github account in settings menu.'
            return
        end

        # Récupération du dépot ET du commit
        begin
            @github_repo = Octokit.repo(params[:repo_id].to_i)
            @last_commit = Octokit.commits(@github_repo.id)
            @last_commit = @last_commit[0]['sha']

        rescue Octokit::Error => e
            redirect_to account_products_path, alert: 'Your repository is not available. We cannot import your product.'
            return
        end

        # Récupération du readme
        begin
            @github_readme = Octokit.readme(current_user.github_login+"/"+@github_repo.name)
            renderer = Redcarpet::Render::HTML.new(prettify: true)
            markdown = Redcarpet::Markdown.new(renderer, fenced_code_blocks: true)
            @github_readme = markdown.render(Base64.decode64(@github_readme.content))
        rescue Octokit::Error => e
            @github_readme = nil
        end

        # Enregistrement du produit
        Product.transaction do

            language = Language.add_language(@github_repo.language == nil ? "Other" : @github_repo.language)

            @product = Product.new
            @product.title                   = @github_repo.name
            @product.description             = @github_readme
            @product.github_repo_id          = @github_repo.id
            @product.github_repo_name        = @github_repo.name
            @product.github_repo_language    = @github_repo.language == nil ? "other" : @github_repo.language.parameterize
            @product.github_repo_type        = @github_repo.private == false ? "public" : "private"
            @product.commit_sha              = @last_commit
            @product.commit_sha_latest       = @last_commit
            @product.user_id                 = current_user.id
            @product.language_id             = language.id
            @product.framework_id            = nil

        end

        if @product.save(validate: false)
            redirect_to edit_account_product_path(@product.id), notice: 'Product has been successfully created.'
        else
            render plain: @product.errors.full_messages
        end


    end

    # --------------------------------------------------------------------------

    # Mettre à jour un produit

    def update

        begin
            @github_repo = Octokit.repo(@product.github_repo_id.to_i)
            @last_commit = Octokit.commits(@github_repo.id)
            @last_commit = @last_commit[0]['sha']

            if @product.commit_sha != @last_commit
                @product.update!(commit_sha_latest: @last_commit)
            end

            rescue Octokit::Error => e
            redirect_to account_products_path, notice: 'Your repository is not available. We cannot update your product.'
            return
        end

        if @product.update(product_params)

            # Vérification du nombre de screenshot et suppression des screenshots en trop
            total_screenshots = @product.screenshots.size
            (3..total_screenshots - 1).each do |screen|
                @product.screenshots[screen].purge
            end

            redirect_to account_products_path, notice: 'Your product has been successfully updated'
        else
            render 'account/products/edit'
        end
    end

    # --------------------------------------------------------------------------

    # Supprimer un produit
    # Suppression du fichier numérique attaché et des screenshots du produit
    # Note : Suppression de type SOFT DELETE (deleted_at = Date de Suppression)

    def destroy

        @product.digital_product.purge
        @product.screenshots.purge

        if @product.destroy
            redirect_to account_products_path, notice: 'Your product has been successfully destroyed.'
        end
    end

    # --------------------------------------------------------------------------
    # REMOTE
    # --------------------------------------------------------------------------

    # Supprimer une capture d'écran du produit

    def delete_screenshot
        @product.screenshots.find_by_id(params[:signed_id]).purge unless @product.screenshots.find_by_id(params[:signed_id]).nil?
    end

    # --------------------------------------------------------------------------

    # Récupère la liste des frameworks d'un language

    def list_frameworks
        @frameworks = Framework.where(language_id: params[:language_id])
        respond_to do |format|
          format.js
        end
    end

    # --------------------------------------------------------------------------
    # PRIVATE
    # --------------------------------------------------------------------------

    private

    def set_octokit_client
        unless current_user.github_token.nil?
            Octokit.configure do |c|
                c.access_token = current_user.github_token
            end
        else
            redirect_to account_settings_path, notice: 'Your account should be linked to a GitHub Account. Please verify your settings.'
            return
        end
    end

    def set_product
        begin
            @product = current_user.products.find(params[:id])
        rescue ActiveRecord::RecordNotFound => e
            redirect_to account_products_path, alert: 'Product not found'
        end
    end

    # --------------------------------------------------------------------------

    def product_params
        params.require(:product).permit(
            :title,
            :description,
            :price,
            :user_id,
            :language_id,
            :framework_id,
            :digital_product,
            :category_id,
            :github_repo_id,
            :github_repo_type,
            :github_repo_language,
            :commit_sha,
            :commit_sha_latest,
            :allow_latest_version,
            screenshots: []
        )
    end
end
