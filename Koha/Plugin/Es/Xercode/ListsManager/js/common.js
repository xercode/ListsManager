// Adapted from https://gist.github.com/jnormore/7418776
function confirmModal(message, title, yes_label, no_label, callback) {
    $("#bootstrap-confirm-box-modal").data('confirm-yes', false);
    if($("#bootstrap-confirm-box-modal").length == 0) {
        $("body").append('<div id="bootstrap-confirm-box-modal" class="modal">\
            <div class="modal-dialog">\
                <div class="modal-content">\
                    <div class="modal-header" style="min-height:40px;">\
                        <button type="button" class="closebtn" data-dismiss="modal" aria-hidden="true">&times;</button>\
                        <h4 class="modal-title"></h4>\
                    </div>\
                    <div class="modal-body"><p></p></div>\
                    <div class="modal-footer">\
                        <a href="#" id="bootstrap-confirm-box-modal-submit" class="btn btn-danger"><i class="fa fa-check" aria-hidden="true"></i></a>\
                        <a href="#" id="bootstrap-confirm-box-modal-cancel" data-dismiss="modal" class="btn btn-default"><i class="fa fa-remove" aria-hidden="true"></i></a>\
                    </div>\
                </div>\
            </div>\
        </div>');
        $("#bootstrap-confirm-box-modal-submit").on('click', function () {
            $("#bootstrap-confirm-box-modal").data('confirm-yes', true);
            $("#bootstrap-confirm-box-modal").modal('hide');
            return false;
        });
        $("#bootstrap-confirm-box-modal").on('hide.bs.modal', function () {
            if(callback) callback($("#bootstrap-confirm-box-modal").data('confirm-yes'));
        });
    }

    $("#bootstrap-confirm-box-modal .modal-header h4").text( title || "" );
    if( message && message != "" ){
        $("#bootstrap-confirm-box-modal .modal-body").html( message || "" );
    } else {
        $("#bootstrap-confirm-box-modal .modal-body").remove();
    }
    $("#bootstrap-confirm-box-modal-submit").text( yes_label || 'Confirm' );
    $("#bootstrap-confirm-box-modal-cancel").text( no_label || 'Cancel' );
    $("#bootstrap-confirm-box-modal").modal('show');
}
