package eu.europa.esig.dss.web.restApiExt;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import eu.europa.esig.dss.model.DSSDocument;
import eu.europa.esig.dss.pdfa.validation.PDFADocumentValidator;
import eu.europa.esig.dss.spi.validation.CertificateVerifier;
import eu.europa.esig.dss.spi.validation.CommonCertificateVerifier;
import eu.europa.esig.dss.validation.reports.Reports;
import eu.europa.esig.dss.ws.converter.RemoteDocumentConverter;
import eu.europa.esig.dss.ws.dto.RemoteDocument;
import eu.europa.esig.dss.ws.validation.common.RemoteDocumentValidationService;
import eu.europa.esig.dss.ws.validation.dto.DataToValidateDTO;
import eu.europa.esig.dss.ws.validation.dto.WSReportsDTO;
import eu.europa.esig.dss.simplereport.jaxb.XmlPDFAInfo;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Component
@Path("/") // base path is /services/rest/validation from CXFConfig
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class ValidateSigPdfAResource {

	@Autowired
	private RemoteDocumentValidationService validationService;

	// CertificateVerifier z kontextu (TSL/OCSP/CRL...), fallback na CommonCertificateVerifier
	@Autowired(required = false)
	private CertificateVerifier certificateVerifier;

	@POST
	@Path("/validateSigPdfA")
	public WSReportsDTO validateSigPdfA(final DataToValidateDTO dto) {
		// 1) standardní validace (stejný výstup jako /validateSignature)
		final WSReportsDTO ws = validationService.validateDocument(dto);

		// 2) bez vstupního dokumentu není co validovat pro PDF/A
		final RemoteDocument signedRemote = (dto != null) ? dto.getSignedDocument() : null;
		if (signedRemote == null) {
			return ws;
		}

		// 3) PDF/A validator + detached obsahy
		final DSSDocument signed = RemoteDocumentConverter.toDSSDocument(signedRemote);
		final List<DSSDocument> detached = RemoteDocumentConverter.toDSSDocuments(dto.getOriginalDocuments());

		final PDFADocumentValidator pdfaValidator = new PDFADocumentValidator(signed);
		if (detached != null && !detached.isEmpty()) {
			pdfaValidator.setDetachedContents(detached);
		}

		// 3a) DŮLEŽITÉ: nastavíme CertificateVerifier (jinak výjimka „CertificateVerifier is not defined“)
		final CertificateVerifier verifier =
			(certificateVerifier != null) ? certificateVerifier : new CommonCertificateVerifier();
		pdfaValidator.setCertificateVerifier(verifier);

		// 4) PDF/A validace (policy předáváme do validateDocument(...), je-li k dispozici)
		final RemoteDocument policyRemote = dto.getPolicy();
		final Reports pdfaReports = (policyRemote != null && policyRemote.getBytes() != null)
				? pdfaValidator.validateDocument(RemoteDocumentConverter.toDSSDocument(policyRemote))
				: pdfaValidator.validateDocument();

		// 5) vytáhneme PDFAInfo a vložíme jej do SimpleReport
		if (pdfaReports != null && pdfaReports.getSimpleReportJaxb() != null) {
			final XmlPDFAInfo pdfaInfo = pdfaReports.getSimpleReportJaxb().getPDFAInfo();
			if (pdfaInfo != null && ws.getSimpleReport() != null) {
				ws.getSimpleReport().setPDFAInfo(pdfaInfo);
			}
		}

		return ws;
	}
}
