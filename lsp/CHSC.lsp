(vl-load-com)

(defun CHSC:3DPoint (pt)
  (vlax-3d-point
    (list
      (float (car pt))
      (float (cadr pt))
      (float (if (caddr pt) (caddr pt) 0.0))
    )
  )
)

(defun CHSC:SafeGet (obj prop / value)
  (if (and obj (vlax-property-available-p obj prop))
    (progn
      (setq value
        (vl-catch-all-apply
          'vlax-get-property
          (list obj prop)
        )
      )
      (if (vl-catch-all-error-p value) nil value)
    )
  )
)

(defun CHSC:SafePut (obj prop value / result)
  (if
    (and
      obj
      (not (null value))
      (vlax-property-available-p obj prop T)
    )
    (progn
      (setq result
        (vl-catch-all-apply
          'vlax-put-property
          (list obj prop value)
        )
      )
      (not (vl-catch-all-error-p result))
    )
  )
)

(defun CHSC:SafeDelete (obj)
  (if obj
    (vl-catch-all-apply 'vla-Delete (list obj))
  )
)

(defun CHSC:GetHandle (ent / data)
  (if (and ent (setq data (entget ent)))
    (cdr (assoc 5 data))
  )
)

(defun CHSC:FindViewportByClip (clipEnt / ss i vp data ref clipHandle refHandle found)
  (setq clipHandle (CHSC:GetHandle clipEnt))
  (setq ss
    (ssget "_X"
      (list
        '(0 . "VIEWPORT")
        (cons 410 (getvar "CTAB"))
      )
    )
  )

  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (null found))
        (setq vp   (ssname ss i))
        (setq data (entget vp))
        (setq ref  (cdr (assoc 340 data)))

        (if ref
          (cond
            ((eq ref clipEnt)
              (setq found vp)
            )
            (clipHandle
              (setq refHandle (CHSC:GetHandle ref))
              (if
                (and refHandle (= (strcase refHandle) (strcase clipHandle)))
                (setq found vp)
              )
            )
          )
        )
        (setq i (1+ i))
      )
    )
  )
  found
)

(defun CHSC:ResolveViewport (ent / data type vp)
  (if (and ent (setq data (entget ent)))
    (progn
      (setq type (cdr (assoc 0 data)))
      (if (= type "VIEWPORT")
        ent
        (CHSC:FindViewportByClip ent)
      )
    )
  )
)

(defun CHSC:GetViewportScale (message / pick ent data layout vpnum obj scale done)
  (while (not done)
    (setq pick (entsel message))

    (if (null pick)
      (setq done T scale nil)
      (progn
        (setq ent (CHSC:ResolveViewport (car pick)))

        (if (null ent)
          (princ "\nThe selected object is not a viewport or viewport clipping boundary.")
          (progn
            (setq data   (entget ent))
            (setq layout (cdr (assoc 410 data)))
            (setq vpnum  (cdr (assoc 69 data)))

            (cond
              ((or (null layout) (/= (strcase layout) (strcase (getvar "CTAB"))))
                (princ "\nThe viewport is not on the current layout.")
              )
              ((or (null vpnum) (<= vpnum 1))
                (princ "\nThe selected object is not a valid layout viewport.")
              )
              (T
                (setq obj (vlax-ename->vla-object ent))
                (setq scale (CHSC:SafeGet obj 'CustomScale))
                (if (and (numberp scale) (> scale 1e-12))
                  (setq done T)
                  (progn
                    (setq scale nil)
                    (princ "\nUnable to read a valid viewport scale.")
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  scale
)

(defun CHSC:PaperObjectP (ent layout / data type owner)
  (if (and ent (setq data (entget ent)))
    (progn
      (setq type  (cdr (assoc 0 data)))
      (setq owner (cdr (assoc 410 data)))
      (and
        owner
        (= (strcase owner) (strcase layout))
        (/= type "VIEWPORT")
      )
    )
  )
)

(defun CHSC:FilterSelection (ss layout / result i ent)
  (setq result (ssadd))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq ent (ssname ss i))
        (if (CHSC:PaperObjectP ent layout)
          (ssadd ent result)
        )
        (setq i (1+ i))
      )
    )
  )
  result
)

(defun CHSC:CaptureSize (obj / props result prop value)
  (setq props
    '(Height
      TextHeight
      ScaleFactor
      XScaleFactor
      YScaleFactor
      ZScaleFactor
      ArrowheadSize
      DoglegLength
      LandingGap
    )
  )

  (foreach prop props
    (setq value (CHSC:SafeGet obj prop))
    (if (numberp value)
      (setq result (cons (cons prop value) result))
    )
  )
  result
)

(defun CHSC:RestoreSize (obj values / item)
  (foreach item values
    (CHSC:SafePut obj (car item) (cdr item))
  )
)

(defun CHSC:DimensionP (ent / data)
  (and ent (setq data (entget ent)) (= (cdr (assoc 0 data)) "DIMENSION"))
)

(defun CHSC:CopyOne (ent baseVar targetVar factor / obj copy size dimScale scaleResult moveResult ok)
  (setq obj (vlax-ename->vla-object ent))
  (setq size (CHSC:CaptureSize obj))

  (if (CHSC:DimensionP ent)
    (setq dimScale (CHSC:SafeGet obj 'LinearScaleFactor))
  )

  (setq copy (vl-catch-all-apply 'vla-Copy (list obj)))

  (if (vl-catch-all-error-p copy)
    nil
    (progn
      (setq scaleResult
        (vl-catch-all-apply
          'vla-ScaleEntity
          (list copy baseVar factor)
        )
      )

      (if (vl-catch-all-error-p scaleResult)
        (progn
          (CHSC:SafeDelete copy)
          nil
        )
        (progn
          (setq moveResult
            (vl-catch-all-apply
              'vla-Move
              (list copy baseVar targetVar)
            )
          )

          (if (vl-catch-all-error-p moveResult)
            (progn
              (CHSC:SafeDelete copy)
              nil
            )
            (progn
              (CHSC:RestoreSize copy size)

              (if
                (and
                  (numberp dimScale)
                  (> (abs factor) 1e-12)
                )
                (CHSC:SafePut copy 'LinearScaleFactor (/ dimScale factor))
              )

              (vl-catch-all-apply 'vla-Update (list copy))
              T
            )
          )
        )
      )
    )
  )
)

(defun CHSC:CopyObjects (ss basePt targetPt factor / i count baseVar targetVar)
  (setq baseVar   (CHSC:3DPoint basePt))
  (setq targetVar (CHSC:3DPoint targetPt))
  (setq i 0 count 0)

  (repeat (sslength ss)
    (if (CHSC:CopyOne (ssname ss i) baseVar targetVar factor)
      (setq count (1+ count))
    )
    (setq i (1+ i))
  )
  count
)

(defun c:CHSC (/ *error* acad doc undoStarted oldCmdecho oldCvport
                 sourceScale targetScale factor ss filtered basePt targetPt count layout)

  (setq acad       (vlax-get-acad-object))
  (setq doc        (vla-get-ActiveDocument acad))
  (setq oldCmdecho (getvar "CMDECHO"))
  (setq oldCvport  (getvar "CVPORT"))

  (defun *error* (msg)
    (if undoStarted
      (progn
        (vl-catch-all-apply 'vla-EndUndoMark (list doc))
        (setq undoStarted nil)
      )
    )

    (if oldCmdecho
      (setvar "CMDECHO" oldCmdecho)
    )

    (if
      (and
        oldCvport
        (= (getvar "TILEMODE") 0)
        (> oldCvport 0)
      )
      (vl-catch-all-apply 'setvar (list "CVPORT" oldCvport))
    )

    (if
      (and
        msg
        (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*,*ABORT*"))
      )
      (princ (strcat "\nCHSC error: " msg))
    )
    (princ)
  )

  (setvar "CMDECHO" 0)

  (cond
    ((= (getvar "TILEMODE") 1)
      (princ "\nCHSC can only run in a layout.")
    )

    (T
      (if (> (getvar "CVPORT") 1)
        (setvar "CVPORT" 1)
      )

      (setq sourceScale
        (CHSC:GetViewportScale
          "\nSelect source viewport or its clipping boundary: "
        )
      )

      (if sourceScale
        (setq targetScale
          (CHSC:GetViewportScale
            "\nSelect target viewport or its clipping boundary: "
          )
        )
      )

      (if (and sourceScale targetScale)
        (progn
          (setq factor (/ targetScale sourceScale))

          (if (> (abs factor) 1e-12)
            (progn
              (princ "\nSelect paper-space objects to copy: ")
              (setq ss (ssget))

              (if ss
                (progn
                  (setq layout   (getvar "CTAB"))
                  (setq filtered (CHSC:FilterSelection ss layout))

                  (if (> (sslength filtered) 0)
                    (progn
                      (setq basePt (getpoint "\nSpecify source reference point: "))

                      (if basePt
                        (setq targetPt
                          (getpoint basePt "\nSpecify corresponding target point: ")
                        )
                      )

                      (if (and basePt targetPt)
                        (progn
                          (vla-StartUndoMark doc)
                          (setq undoStarted T)

                          (setq count
                            (CHSC:CopyObjects filtered basePt targetPt factor)
                          )

                          (vla-EndUndoMark doc)
                          (setq undoStarted nil)

                          (princ
                            (strcat
                              "\nCHSC completed. Copied "
                              (itoa count)
                              " object(s)."
                            )
                          )
                        )
                      )
                    )
                    (princ "\nNo valid paper-space objects were selected.")
                  )
                )
              )
            )
            (princ "\nInvalid viewport scale ratio.")
          )
        )
      )
    )
  )

  (if undoStarted
    (vla-EndUndoMark doc)
  )
  (setvar "CMDECHO" oldCmdecho)
  (princ)
)

(princ "\nCHSC loaded.")
(princ)
